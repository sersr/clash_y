package profilerefresh

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// ConfigFileName is the config mihomo loads from its home directory.
const ConfigFileName = "config.yaml"

// RefreshFile rewrites the config of dir from the subscription at url: it
// downloads the subscription, applies script, overlays the app-owned keys of
// the config already on disk and writes the result back to dir/config.yaml.
//
// The previous file is kept at config.yaml.bak so a caller that restarts the
// core can roll back when the new configuration is rejected; the caller removes
// the backup once the new config is running.
//
// The desktop daemon, the Android VPN service and the iOS Packet Tunnel all
// refresh through this function, so a background refresh writes the same file a
// refresh started from the app would.
func RefreshFile(dir string, url string, script string) error {
	if strings.TrimSpace(dir) == "" {
		return errors.New("config dir is empty")
	}

	path := filepath.Join(dir, ConfigFileName)
	// The daemon runs privileged and the mobile config directories are shared
	// with the app: the file written here has to be the real file inside the
	// directory, never a link planted by a less privileged writer.
	info, err := os.Lstat(path)
	if err != nil {
		return fmt.Errorf("read config file: %w", err)
	}
	if info.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("refusing to follow a symlinked config file: %s", path)
	}
	if !info.Mode().IsRegular() {
		return fmt.Errorf("config file is not a regular file: %s", path)
	}

	current, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("read current config: %w", err)
	}

	configured, err := Refresh(url, script, string(current))
	if err != nil {
		return err
	}

	backupPath := path + ".bak"
	if err := os.WriteFile(backupPath, current, 0o644); err != nil {
		return fmt.Errorf("back up config: %w", err)
	}
	if err := os.WriteFile(path, []byte(configured), 0o644); err != nil {
		_ = os.Remove(backupPath)
		return fmt.Errorf("write config: %w", err)
	}
	return nil
}
