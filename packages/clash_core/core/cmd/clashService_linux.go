//go:build linux

package main

import (
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"regexp"
	"strings"
	"syscall"

	"mihomo-so/tunbroker"
)

const (
	tunHelperUnitPath   = "/etc/systemd/system/clashy-tun-helper.service"
	tunHelperUnitName   = "clashy-tun-helper.service"
	tunHelperName       = "clashyTunHelper"
	tunHelperAllowedUID = "0"
)

// runPlatformService is the systemd entry point. Both SIGTERM and SIGINT stop
// the core before exiting so no TUN device or helper lease is left behind.
func runPlatformService() {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	done := make(chan error, 1)
	go func() { done <- serve(ctx, nil) }()

	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGTERM, syscall.SIGINT)

	select {
	case <-signals:
		cancel()
		<-done
		os.Exit(0)
	case err := <-done:
		if err != nil {
			logf("clashService failed: %v", err)
			os.Exit(1)
		}
	}
}

// ensureTunHelper installs the root-run systemd unit that creates the TUN
// interface. clashService itself runs as root here, so the helper only accepts
// UID 0; desktop users still drive the VPN through this control API.
func ensureTunHelper() error {
	executable, err := os.Executable()
	if err != nil {
		return fmt.Errorf("resolve clashService executable: %w", err)
	}
	helperPath := filepath.Join(filepath.Dir(executable), tunHelperName)
	if _, err := os.Stat(helperPath); err != nil {
		return fmt.Errorf("bundled Linux TUN helper is missing: %s", helperPath)
	}

	expectedUnit := tunHelperUnit(helperPath)
	currentUnit := ""
	if payload, err := os.ReadFile(tunHelperUnitPath); err != nil {
		if !errors.Is(err, os.ErrNotExist) {
			return fmt.Errorf("read TUN helper unit: %w", err)
		}
	} else {
		currentUnit = string(payload)
	}

	running := systemdUnitActive()

	if currentUnit != expectedUnit || !running {
		exitCode, err := installTunHelperUnit(expectedUnit)
		if err != nil {
			return err
		}
		if exitCode != 0 {
			return fmt.Errorf("install Linux TUN helper failed (exit %d)", exitCode)
		}
	}

	return waitUntilUnixSocketReady(tunbroker.SocketPath, socketReadyTimeout)
}

func tunHelperUnit(helperPath string) string {
	exec := helperPath
	if strings.Contains(helperPath, " ") {
		exec = `"` + helperPath + `"`
	}
	return fmt.Sprintf(`[Unit]
Description=Clashy TUN Helper
After=network.target

[Service]
Type=simple
ExecStart=%s --allowed-uid %s
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
`, exec, tunHelperAllowedUID)
}

func systemdUnitActive() bool {
	_, err := commandOutput("systemctl", "is-active", "--quiet", tunHelperUnitName)
	return err == nil
}

func installTunHelperUnit(unit string) (int, error) {
	script := fmt.Sprintf(`set -e
mkdir -p /etc/systemd/system
cat > %s <<'EOF'
%sEOF
systemctl daemon-reload
systemctl enable %s
systemctl restart %s
`, tunHelperUnitPath, unit, tunHelperUnitName, tunHelperUnitName)

	encoded := base64.StdEncoding.EncodeToString([]byte(script))
	shellCommand := fmt.Sprintf("echo '%s' | base64 -d | sh", encoded)

	// The daemon itself runs as root; manual debugging as a regular user goes
	// through pkexec, mirroring the Dart service.
	command := "sh"
	arguments := []string{"-c", shellCommand}
	if !isRoot() {
		command = "pkexec"
		arguments = []string{"sh", "-c", shellCommand}
	}
	output, err := commandOutput(command, arguments...)
	if err != nil {
		var exitErr *execExitError
		if errors.As(err, &exitErr) {
			if output != "" {
				logf("%s", output)
			}
			return exitErr.code, nil
		}
		return 0, fmt.Errorf("install Linux TUN helper: %w", err)
	}
	if output != "" {
		logf("%s", output)
	}
	return 0, nil
}

func isRoot() bool {
	userId, err := commandOutput("id", "-u")
	return err == nil && userId == "0"
}

// listTunInterfaces has no macOS-style kernel-assigned TUN name to track: the
// Linux helper always creates tunbroker.InterfaceName.
func listTunInterfaces() ([]string, error) { return nil, nil }

// tunInterfaceHealthy reports whether the helper's TUN device is still up.
func tunInterfaceHealthy(iface string) bool {
	output, err := commandOutput("ip", "link", "show", iface)
	if err != nil {
		return false
	}
	return regexp.MustCompile(`\bUP\b`).MatchString(output)
}
