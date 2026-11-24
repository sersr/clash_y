//go:build darwin

package main

import (
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"regexp"
	"strings"
	"syscall"
	"time"

	"mihomo-so/tunbroker"
)

const (
	tunHelperLabel       = "com.aote.clashy.tun-helper"
	tunHelperPlistPath   = "/Library/LaunchDaemons/com.aote.clashy.tun-helper.plist"
	tunHelperInstallPath = "/Library/PrivilegedHelperTools/com.aote.clashy.tun-helper"

	trayExecutableName = "clashyTray"
	tunHelperName      = "clashyTunHelper"

	helperReadyTimeout = 15 * time.Second
)

// runPlatformService is the LaunchAgent entry point: start the tray helper,
// serve the control API and stop the core when launchd sends SIGTERM.
func runPlatformService() {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	appPath := argumentValue("--app")
	serviceSocket := argumentValue("--service-socket")
	if serviceSocket == "" {
		serviceSocket = serviceSocketUnixPath
	}
	clashSocket := argumentValue("--clash-socket")
	if clashSocket == "" {
		clashSocket = serviceSocketUnixPath
	}

	var tray *exec.Cmd
	if appPath != "" {
		tray = startTray(appPath, serviceSocket, clashSocket)
	}

	done := make(chan error, 1)
	go func() { done <- serve(ctx, nil) }()

	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGTERM)

	select {
	case <-signals:
		if tray != nil && tray.Process != nil {
			_ = tray.Process.Kill()
		}
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

func startTray(appPath string, serviceSocket string, clashSocket string) *exec.Cmd {
	executable, err := os.Executable()
	if err != nil {
		logf("resolve clashService executable failed: %v", err)
		return nil
	}
	trayPath := filepath.Join(filepath.Dir(executable), trayExecutableName)

	command := exec.Command(trayPath,
		"--app", appPath,
		"--service-socket", serviceSocket,
		"--clash-socket", clashSocket,
	)
	command.Dir = appPath
	command.Stdout = os.Stderr
	command.Stderr = os.Stderr
	if err := command.Start(); err != nil {
		logf("start Clashy Tray executable failed: %v", err)
		return nil
	}
	go func() {
		if err := command.Wait(); err != nil {
			logf("Clashy Tray exited: %v", err)
		} else {
			logf("Clashy Tray exited")
		}
	}()
	return command
}

// ensureTunHelper installs and starts the privileged LaunchDaemon that creates
// the TUN interface. Everything privileged is routed through a single
// administrator prompt.
func ensureTunHelper() error {
	executable, err := os.Executable()
	if err != nil {
		return fmt.Errorf("resolve clashService executable: %w", err)
	}
	helperPath := filepath.Join(filepath.Dir(executable), tunHelperName)
	if _, err := os.Stat(helperPath); err != nil {
		return fmt.Errorf("bundled macOS TUN helper is missing: %s", helperPath)
	}

	userId, err := commandOutput("/usr/bin/id", "-u")
	if err != nil {
		return fmt.Errorf("resolve current user: %w", err)
	}
	if !regexp.MustCompile(`^\d+$`).MatchString(userId) || userId == "0" {
		return fmt.Errorf("unexpected user ID: %s", userId)
	}

	bundledHash, err := fileHash(helperPath)
	if err != nil {
		return err
	}
	installedHash, err := fileHash(tunHelperInstallPath)
	if err != nil {
		return err
	}

	expectedPlist := launchDaemonPlist(userId)
	currentPlist := ""
	if payload, err := os.ReadFile(tunHelperPlistPath); err != nil {
		if !errors.Is(err, os.ErrNotExist) {
			return fmt.Errorf("read TUN helper plist: %w", err)
		}
	} else {
		currentPlist = string(payload)
	}

	running := launchdRunning()

	if bundledHash != installedHash || currentPlist != expectedPlist || !running {
		if err := installTunHelper(helperPath, expectedPlist); err != nil {
			return err
		}
		if err := waitUntilLaunchdRunning(); err != nil {
			return err
		}
	}

	// launchd reporting "running" only means the process started; mihomo fails
	// as soon as it connects before the helper has listened on its socket.
	return waitUntilUnixSocketReady(tunbroker.SocketPath, socketReadyTimeout)
}

func installTunHelper(helperPath string, plist string) error {
	plistBase64 := base64.StdEncoding.EncodeToString([]byte(plist))
	script := fmt.Sprintf(`if /bin/launchctl print "system/%s" >/dev/null 2>&1; then
  /bin/launchctl bootout "system/%s" || exit $?
fi
/usr/bin/install -o root -g wheel -m 755 %s %s || exit $?
printf '%%s' '%s' | /usr/bin/base64 -D > '%s' || exit $?
/usr/sbin/chown root:wheel '%s' || exit $?
/bin/chmod 644 '%s' || exit $?
/bin/launchctl bootstrap system '%s' || exit $?
/bin/launchctl enable "system/%s" || exit $?
`,
		tunHelperLabel,
		tunHelperLabel,
		shellQuote(helperPath),
		shellQuote(tunHelperInstallPath),
		plistBase64,
		tunHelperPlistPath,
		tunHelperPlistPath,
		tunHelperPlistPath,
		tunHelperPlistPath,
		tunHelperLabel,
	)

	encoded := base64.StdEncoding.EncodeToString([]byte(script))
	appleScript := fmt.Sprintf(
		"do shell script \"printf '%%s' '%s' | /usr/bin/base64 -D | /bin/bash\" with administrator privileges",
		encoded,
	)
	if _, err := commandOutput("/usr/bin/osascript", "-e", appleScript); err != nil {
		return fmt.Errorf("install macOS TUN helper: %w", err)
	}
	return nil
}

func launchDaemonPlist(userId string) string {
	return fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>%s</string>
  <key>ProgramArguments</key>
  <array>
    <string>%s</string>
    <string>--allowed-uid</string>
    <string>%s</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
</dict>
</plist>
`, tunHelperLabel, tunHelperInstallPath, userId)
}

func launchdRunning() bool {
	output, err := commandOutput("/bin/launchctl", "print", "system/"+tunHelperLabel)
	return err == nil && strings.Contains(output, "state = running")
}

func waitUntilLaunchdRunning() error {
	deadline := time.Now().Add(helperReadyTimeout)
	for time.Now().Before(deadline) {
		if launchdRunning() {
			return nil
		}
		time.Sleep(100 * time.Millisecond)
	}
	return errors.New("macOS privileged TUN helper did not become ready")
}

func fileHash(path string) (string, error) {
	if _, err := os.Stat(path); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return "", nil
		}
		return "", fmt.Errorf("stat %s: %w", path, err)
	}
	output, err := commandOutput("/usr/bin/shasum", "-a", "256", path)
	if err != nil {
		return "", fmt.Errorf("hash %s: %w", path, err)
	}
	return strings.Fields(output)[0], nil
}

// listTunInterfaces returns the utun devices currently visible to the kernel.
func listTunInterfaces() ([]string, error) {
	output, err := commandOutput("/sbin/ifconfig", "-l")
	if err != nil {
		return nil, fmt.Errorf("list macOS interfaces: %w", err)
	}
	var interfaces []string
	for _, name := range strings.Fields(output) {
		if strings.HasPrefix(name, "utun") {
			interfaces = append(interfaces, name)
		}
	}
	return interfaces, nil
}

// tunInterfaceHealthy reports whether the utun device is still up after a wake.
func tunInterfaceHealthy(iface string) bool {
	output, err := commandOutput("/sbin/ifconfig", iface)
	if err != nil {
		return false
	}
	firstLine, _, _ := strings.Cut(output, "\n")
	return regexp.MustCompile(`flags=\d+<[^>]*\bUP\b`).MatchString(firstLine)
}
