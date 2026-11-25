// Package geoensure downloads the GeoIP/GeoSite databases a configuration
// needs before mihomo parses it.
//
// mihomo downloads a missing database lazily while it parses rules, and a
// failed download aborts the whole parse. On networks where
// cdn.jsdelivr.net is unreliable — mainland China is the common case — that
// killed the Android VPN start after the TUN interface had already been
// established, which the user only perceives as "the VPN does not turn on".
//
// Downloading up front across several mirrors keeps startup independent of a
// single CDN; a broken mirror becomes a warning instead of a failed start.
package geoensure

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	C "github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/log"
)

// mirrorTemplates serve MetaCubeX/meta-rules-dat; %s is the asset name.
//
// gh-proxy is first because it works from mainland China, where
// cdn.jsdelivr.net frequently answers with a truncated body or EOF. The
// jsdelivr endpoints stay as fallbacks for networks that block gh-proxy.
var mirrorTemplates = []string{
	"https://gh-proxy.com/https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/%s",
	"https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/%s",
	"https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/%s",
}

const (
	// attemptTimeout bounds one mirror attempt so a dead CDN cannot stall the
	// start for the 90s mihomo itself allows.
	attemptTimeout = 20 * time.Second
	// minFileSize rejects truncated downloads; every database is megabytes.
	minFileSize = 256 << 10
)

// File is one database: the asset name on the mirror and where mihomo expects
// it inside its home directory.
type File struct {
	Name string
	Path string
}

// Ensure downloads the databases the configuration at configPath references
// that are not on disk yet. It never fails the caller: mihomo reports a still
// missing database itself, and a startup that can work without the file
// should not be aborted here.
func Ensure(configPath string) {
	body, err := os.ReadFile(configPath)
	if err != nil {
		// A missing or unreadable config is mihomo's problem to report.
		return
	}

	for _, file := range Needed(body) {
		if usable(file.Path) {
			continue
		}
		if err := download(file); err != nil {
			log.Warnln("[clashy] %s is not available: %s", file.Name, err)
		}
	}
}

// Needed returns the databases the configuration references, in download
// order. Paths come from mihomo's global home directory, so the caller must
// have called constant.SetHomeDir first.
func Needed(config []byte) []File {
	text := strings.ToUpper(string(config))
	var files []File

	if strings.Contains(text, "GEOSITE") {
		files = append(files, File{Name: "geosite.dat", Path: C.Path.GeoSite()})
	}

	if strings.Contains(text, "GEOIP") || strings.Contains(text, "IP-ASN") {
		if geodataModeEnabled(config) {
			files = append(files, File{Name: "geoip.dat", Path: C.Path.GeoIP()})
		} else {
			files = append(files, File{Name: "geoip.metadb", Path: C.Path.MMDB()})
		}
	}

	return files
}

// geodataModeEnabled reads `geodata-mode` from the YAML text. Only the
// top-level key matters, and comments are skipped so a documented example
// does not trigger a download.
func geodataModeEnabled(config []byte) bool {
	for _, line := range strings.Split(string(config), "\n") {
		trimmed := strings.ToLower(strings.TrimSpace(line))
		if strings.HasPrefix(trimmed, "#") {
			continue
		}
		if !strings.HasPrefix(trimmed, "geodata-mode:") {
			continue
		}
		return strings.Contains(trimmed, "true")
	}
	return false
}

// usable reports whether path already holds a complete download.
func usable(path string) bool {
	if path == "" {
		return false
	}
	info, err := os.Stat(path)
	return err == nil && info.Size() >= minFileSize
}

func download(file File) error {
	var attempts []string
	for _, template := range mirrorTemplates {
		url := fmt.Sprintf(template, file.Name)
		if err := fetch(url, file.Path); err != nil {
			attempts = append(attempts, fmt.Sprintf("%s: %s", url, err))
			continue
		}
		log.Infoln("[clashy] downloaded %s from %s", file.Name, url)
		return nil
	}
	return errors.New(strings.Join(attempts, "; "))
}

// fetch writes url to path atomically: a partial body never replaces a usable
// file, and a truncated body is rejected by its size.
func fetch(url string, path string) error {
	ctx, cancel := context.WithTimeout(context.Background(), attemptTimeout)
	defer cancel()

	request, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return err
	}
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()

	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("unexpected status %s", response.Status)
	}

	dir := filepath.Dir(path)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}

	temp := path + ".download"
	file, err := os.Create(temp)
	if err != nil {
		return err
	}
	written, copyErr := io.Copy(file, response.Body)
	closeErr := file.Close()
	if copyErr != nil {
		os.Remove(temp)
		return copyErr
	}
	if closeErr != nil {
		os.Remove(temp)
		return closeErr
	}
	if written < minFileSize {
		os.Remove(temp)
		return fmt.Errorf("truncated body: %d bytes", written)
	}

	return os.Rename(temp, path)
}
