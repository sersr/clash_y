//go:build windows

package main

import (
	"context"
	"errors"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"

	"github.com/tailscale/go-winio"
	"golang.org/x/sys/windows/svc"
)

const (
	// serviceName is the SCM name the Flutter app installs and controls.
	serviceName = "clashy_service"

	tunHelperServiceName  = "clashy_tun_helper"
	tunHelperExecutable   = "clashyTunHelper.exe"
	tunHelperReadyTimeout = 10 * time.Second

	serviceStateRunning = 4
)

var (
	serviceStatePattern   = regexp.MustCompile(`STATE\s*:\s*(\d+)`)
	serviceBinPathPattern = regexp.MustCompile(`(?m)^\s*BINARY_PATH_NAME\s*:\s*(.+)$`)

	// scExecutable is resolved explicitly: service processes can start with a
	// PATH that does not include System32.
	scExecutable = func() string {
		if root := os.Getenv("SystemRoot"); root != "" {
			candidate := filepath.Join(root, "System32", "sc.exe")
			if _, err := os.Stat(candidate); err == nil {
				return candidate
			}
		}
		return "sc"
	}()
)

// runPlatformService runs as an SCM service when started by the service control
// manager, and as a plain console process when launched from a terminal.
func runPlatformService() {
	isService, err := svc.IsWindowsService()
	if err != nil {
		logf("detect Windows service context failed: %v", err)
		os.Exit(1)
	}
	if !isService {
		if err := serve(context.Background(), nil); err != nil {
			logf("clashService failed: %v", err)
			os.Exit(1)
		}
		return
	}
	if err := svc.Run(serviceName, windowsService{}); err != nil {
		logf("run Windows service failed: %v", err)
		os.Exit(1)
	}
}

type windowsService struct{}

func (windowsService) Execute(
	_ []string,
	requests <-chan svc.ChangeRequest,
	changes chan<- svc.Status,
) (bool, uint32) {
	changes <- svc.Status{State: svc.StartPending}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	ready := make(chan struct{})
	done := make(chan error, 1)
	go func() { done <- serve(ctx, ready) }()

	select {
	case <-ready:
		changes <- svc.Status{
			State:   svc.Running,
			Accepts: svc.AcceptStop | svc.AcceptShutdown,
		}
	case err := <-done:
		if err != nil {
			logf("clashService stopped during startup: %v", err)
			return true, 1
		}
		return false, 0
	}

	for {
		select {
		case request := <-requests:
			switch request.Cmd {
			case svc.Interrogate:
				changes <- request.CurrentStatus
			case svc.Stop, svc.Shutdown:
				// Stopping the core closes the TUN adapter and its routes before
				// the service reports STOPPED.
				changes <- svc.Status{State: svc.StopPending}
				cancel()
				if err := <-done; err != nil {
					logf("clashService stop failed: %v", err)
					return true, 1
				}
				return false, 0
			}
		case err := <-done:
			if err != nil {
				logf("clashService stopped: %v", err)
				return true, 1
			}
			return false, 0
		}
	}
}

// listenServiceEndpoint creates the control named pipe. On POSIX the socket is
// world-writable for desktop users; here the descriptor grants SYSTEM and
// administrators full access while letting local desktop users reach the API.
// The service itself runs as LocalSystem (see the installer), so it keeps full
// access as the pipe creator.
func listenServiceEndpoint(path string) (net.Listener, error) {
	listener, err := winio.ListenPipe(path, &winio.PipeConfig{
		SecurityDescriptor: "D:(A;;GA;;;SY)(A;;GA;;;BA)(A;;GA;;;BU)",
		InputBufferSize:    64 * 1024,
		OutputBufferSize:   64 * 1024,
	})
	if err != nil {
		return nil, fmt.Errorf("listen on Clash service pipe: %w", err)
	}
	return listener, nil
}

// ensureTunHelper makes sure the privileged Windows service that provisions the
// Wintun adapter is installed and running.
//
// The installer registers the helper in the same elevated script that creates
// clashService, so a normal installation arrives with the helper already
// running. This function covers the other cases: a console run from an
// administrator prompt, an app update that moved the bundled helper, and a
// helper that was stopped. When the caller is not allowed to manage services it
// falls through to the pipe client, which reports whether the helper is usable.
func ensureTunHelper() error {
	executable, err := os.Executable()
	if err != nil {
		return fmt.Errorf("resolve clashService executable: %w", err)
	}
	helperPath := filepath.Join(filepath.Dir(executable), tunHelperExecutable)
	if _, err := os.Stat(helperPath); err != nil {
		return fmt.Errorf("bundled Windows TUN helper is missing: %s", helperPath)
	}

	state, queryErr := queryServiceState(tunHelperServiceName)
	if queryErr != nil {
		if isServiceMissing(queryErr) {
			return installTunHelperService(helperPath)
		}
		if isAccessDenied(queryErr) {
			// The caller may use the helper but not manage it; leave the
			// readiness decision to the pipe client that follows.
			logf("Windows TUN helper service cannot be managed from this account: %v", queryErr)
			return nil
		}
		return fmt.Errorf("query Windows TUN helper service: %w", queryErr)
	}
	if state == serviceStateRunning {
		return nil
	}

	if current, ok := tunHelperBinPath(); ok && !sameWindowsPath(current, helperPath) {
		// The bundled helper moved (app update or relocation).
		if output, configErr := runSC("config", tunHelperServiceName, "binPath=", quotedBinPath(helperPath), "start=", "auto"); configErr != nil {
			logf("update Windows TUN helper service failed: %v%s", configErr, scDetails(output))
		}
	}
	if output, startErr := runSC("start", tunHelperServiceName); startErr != nil {
		// 1056 means "already running", which the readiness poll verifies.
		if current, currentErr := queryServiceState(tunHelperServiceName); currentErr != nil || current != serviceStateRunning {
			return fmt.Errorf("start Windows TUN helper service: %w%s", startErr, scDetails(output))
		}
	}
	return waitUntilTunHelperRunning()
}

// installTunHelperService creates the helper service for the case where the
// installer has not run yet (an administrator console run, or a machine that
// still has the previous installation).
func installTunHelperService(helperPath string) error {
	output, err := runSC("create", tunHelperServiceName, "binPath=", quotedBinPath(helperPath), "start=", "auto")
	if err != nil {
		return fmt.Errorf(
			"create Windows TUN helper service (restart Clashy so its installer registers it): %w%s",
			err,
			scDetails(output),
		)
	}
	if output, err := runSC("description", tunHelperServiceName, "Clashy TUN Helper"); err != nil {
		logf("describe Windows TUN helper service failed: %v%s", err, scDetails(output))
	}
	if output, err := runSC("failure", tunHelperServiceName, "reset=", "60",
		"actions=", "restart/5000/restart/5000/restart/5000/restart/5000/restart/5000"); err != nil {
		logf("configure Windows TUN helper recovery failed: %v%s", err, scDetails(output))
	}
	if output, err := runSC("start", tunHelperServiceName); err != nil {
		if _, currentErr := queryServiceState(tunHelperServiceName); currentErr != nil {
			return fmt.Errorf("start Windows TUN helper service: %w%s", err, scDetails(output))
		}
	}
	return waitUntilTunHelperRunning()
}

func quotedBinPath(path string) string { return `"` + path + `"` }

// runSC invokes the service control tool and returns its combined output.
func runSC(args ...string) (string, error) {
	output, err := exec.Command(scExecutable, args...).CombinedOutput()
	return strings.TrimSpace(string(output)), err
}

// scDetails formats the tail of an `sc` failure for a log line or an API error.
//
// `sc` prints its messages in the console code page (GBK on Chinese Windows),
// which reaches this process as unreadable bytes, so only the printable ASCII
// part is kept: the Win32 error code carried by the error itself is what callers
// need to act on.
func scDetails(output string) string {
	var builder strings.Builder
	for _, char := range strings.TrimSpace(output) {
		switch {
		case char == '\r' || char == '\n' || char == '\t':
			builder.WriteByte(' ')
		case char >= 0x20 && char < 0x7f:
			builder.WriteRune(char)
		}
	}
	details := strings.Join(strings.Fields(builder.String()), " ")
	if details == "" {
		return ""
	}
	return ": " + details
}

// queryServiceState reads the numeric STATE of a service. A stopped or missing
// service is not an error: `sc query` exits with 1060 when it does not exist and
// 5 when the caller may not manage services, both of which the caller inspects.
func queryServiceState(name string) (int, error) {
	output, err := runSC("query", name)
	if err != nil {
		return 0, err
	}
	match := serviceStatePattern.FindStringSubmatch(output)
	if match == nil {
		return 0, errors.New("sc query printed no STATE line")
	}
	state, convErr := strconv.Atoi(match[1])
	if convErr != nil {
		return 0, fmt.Errorf("parse service state %q: %w", match[1], convErr)
	}
	return state, nil
}

// scExitCode returns the Win32 error code `sc` exited with.
func scExitCode(err error) int {
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		return exitErr.ExitCode()
	}
	return -1
}

// isServiceMissing reports the SCM error for "no service with that name".
func isServiceMissing(err error) bool { return scExitCode(err) == 1060 }

// isAccessDenied reports the SCM error for "caller may not manage the service".
func isAccessDenied(err error) bool { return scExitCode(err) == 5 }

func tunHelperBinPath() (string, bool) {
	output, err := runSC("qc", tunHelperServiceName)
	if err != nil {
		return "", false
	}
	match := serviceBinPathPattern.FindStringSubmatch(output)
	if match == nil {
		return "", false
	}
	return strings.TrimSpace(match[1]), true
}

func waitUntilTunHelperRunning() error {
	deadline := time.Now().Add(tunHelperReadyTimeout)
	for time.Now().Before(deadline) {
		if state, err := queryServiceState(tunHelperServiceName); err == nil && state == serviceStateRunning {
			return nil
		}
		time.Sleep(100 * time.Millisecond)
	}
	output, _ := runSC("query", tunHelperServiceName)
	return fmt.Errorf("Windows TUN helper did not reach RUNNING: %s", output)
}

// sameWindowsPath compares an `sc qc` BINARY_PATH_NAME with the bundled helper.
func sameWindowsPath(current string, expected string) bool {
	normalized := strings.TrimSpace(current)
	// `sc qc` may keep the quotes used when the service was created.
	if len(normalized) > 1 && strings.HasPrefix(normalized, `"`) && strings.HasSuffix(normalized, `"`) {
		normalized = normalized[1 : len(normalized)-1]
	}
	return strings.EqualFold(filepath.Clean(normalized), filepath.Clean(expected))
}

func closeFileDescriptor(int) error { return nil }

func listTunInterfaces() ([]string, error) { return nil, nil }

// tunInterfaceHealthy asks the adapter status, which is the same check the Dart
// service performed through PowerShell.
func tunInterfaceHealthy(iface string) bool {
	script := fmt.Sprintf(
		"(Get-NetAdapter -Name '%s' -IncludeHidden -ErrorAction SilentlyContinue).Status",
		strings.ReplaceAll(iface, "'", "''"),
	)
	output, err := exec.Command(
		"powershell.exe",
		"-NoProfile",
		"-NonInteractive",
		"-Command",
		script,
	).Output()
	if err != nil {
		return false
	}
	return strings.EqualFold(strings.TrimSpace(string(output)), "up")
}
