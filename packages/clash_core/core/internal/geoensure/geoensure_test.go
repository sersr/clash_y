package geoensure

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	C "github.com/metacubex/mihomo/constant"
)

// homeDir points mihomo at a temporary directory so Needed resolves paths
// inside it instead of the developer's own home directory.
func homeDir(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	C.SetHomeDir(dir)
	return dir
}

// useMirrors replaces the mirror list for the duration of the test.
func useMirrors(t *testing.T, templates ...string) {
	t.Helper()
	original := mirrorTemplates
	t.Cleanup(func() { mirrorTemplates = original })
	mirrorTemplates = templates
}

// mirrorServer serves payload for every asset name and returns its URL
// template.
func mirrorServer(t *testing.T, payload []byte) string {
	t.Helper()
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if payload == nil {
			http.Error(w, "gone", http.StatusGone)
			return
		}
		w.Write(payload)
	}))
	t.Cleanup(server.Close)
	return server.URL + "/%s"
}

func writeConfig(t *testing.T, dir string, body string) string {
	t.Helper()
	path := filepath.Join(dir, "config.yaml")
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestNeededGeoSite(t *testing.T) {
	dir := homeDir(t)
	files := Needed([]byte("rules:\n  - GEOSITE,CN,全局直连\n  - MATCH,DIRECT\n"))
	if len(files) != 1 {
		t.Fatalf("expected one file, got %+v", files)
	}
	if files[0].Name != "geosite.dat" {
		t.Fatalf("unexpected asset: %+v", files[0])
	}
	if filepath.Base(files[0].Path) != "GeoSite.dat" {
		t.Fatalf("unexpected path: %s", files[0].Path)
	}
	if filepath.Dir(files[0].Path) != dir {
		t.Fatalf("path is outside the home directory: %s", files[0].Path)
	}
}

func TestNeededGeoIPUsesMMDBByDefault(t *testing.T) {
	files := Needed([]byte("rules:\n  - GEOIP,CN,DIRECT\n"))
	if len(files) != 1 || files[0].Name != "geoip.metadb" {
		t.Fatalf("expected the mmdb asset, got %+v", files)
	}
}

func TestNeededGeoIPUsesDatInGeodataMode(t *testing.T) {
	files := Needed([]byte("geodata-mode: true\nrules:\n  - GEOIP,CN,DIRECT\n"))
	if len(files) != 1 || files[0].Name != "geoip.dat" {
		t.Fatalf("expected the dat asset, got %+v", files)
	}
}

func TestNeededIgnoresCommentsAndUnrelatedRules(t *testing.T) {
	files := Needed([]byte("# geodata-mode: true\nrules:\n  - MATCH,DIRECT\n"))
	if len(files) != 0 {
		t.Fatalf("expected no downloads, got %+v", files)
	}
}

func TestNeededReturnsBothDatabases(t *testing.T) {
	files := Needed([]byte("rules:\n  - GEOSITE,CN,DIRECT\n  - GEOIP,CN,DIRECT\n"))
	if len(files) != 2 {
		t.Fatalf("expected two files, got %+v", files)
	}
}

func TestEnsureSkipsCompleteFile(t *testing.T) {
	dir := homeDir(t)
	path := filepath.Join(dir, "GeoSite.dat")
	if err := os.WriteFile(path, make([]byte, minFileSize+1), 0o644); err != nil {
		t.Fatal(err)
	}

	var requests int
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests++
	}))
	t.Cleanup(server.Close)
	useMirrors(t, server.URL+"/%s")

	Ensure(writeConfig(t, dir, "rules:\n  - GEOSITE,CN,DIRECT\n"))
	if requests != 0 {
		t.Fatalf("expected no request, got %d", requests)
	}
}

func TestEnsureFallsBackToSecondMirror(t *testing.T) {
	dir := homeDir(t)
	payload := make([]byte, minFileSize+1)
	for index := range payload {
		payload[index] = byte(index)
	}

	// The first mirror is unreachable, the second one carries the payload.
	useMirrors(t, "http://127.0.0.1:1/%s", mirrorServer(t, payload))
	Ensure(writeConfig(t, dir, "rules:\n  - GEOSITE,CN,DIRECT\n"))

	got, err := os.ReadFile(filepath.Join(dir, "GeoSite.dat"))
	if err != nil {
		t.Fatalf("expected the file to be downloaded: %s", err)
	}
	if len(got) != len(payload) {
		t.Fatalf("unexpected size %d", len(got))
	}
}

func TestEnsureRejectsTruncatedBody(t *testing.T) {
	dir := homeDir(t)
	useMirrors(t, mirrorServer(t, []byte("too short")))
	Ensure(writeConfig(t, dir, "rules:\n  - GEOSITE,CN,DIRECT\n"))

	if _, err := os.Stat(filepath.Join(dir, "GeoSite.dat")); !os.IsNotExist(err) {
		t.Fatalf("a truncated body must not be kept")
	}
	if _, err := os.Stat(filepath.Join(dir, "GeoSite.dat.download")); !os.IsNotExist(err) {
		t.Fatalf("the temporary file must be removed")
	}
}

func TestEnsureKeepsExistingFileWhenDownloadFails(t *testing.T) {
	dir := homeDir(t)
	path := filepath.Join(dir, "GeoSite.dat")
	existing := make([]byte, minFileSize+1)
	if err := os.WriteFile(path, existing, 0o644); err != nil {
		t.Fatal(err)
	}

	useMirrors(t, "http://127.0.0.1:1/%s")
	Ensure(writeConfig(t, dir, "rules:\n  - GEOSITE,CN,DIRECT\n"))

	got, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != len(existing) {
		t.Fatalf("the existing file must be left untouched")
	}
}
