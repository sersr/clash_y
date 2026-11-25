//go:build windows

package main

import (
	"context"
	"fmt"
	"net"
	"os"
	"os/exec"
	"strings"

	"github.com/tailscale/go-winio"
	"golang.org/x/sys/windows/svc"
)

// serviceName is the SCM name the Flutter app installs and controls. The
// service runs as LocalSystem, so it creates and configures the Wintun adapter
// itself instead of delegating that to a separate privileged helper.
const serviceName = "clashy_service"

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

// listenServiceEndpoint creates the control named pipe.
//
// The control API drives a LocalSystem service, so the DACL only grants the
// installing user (passed by the installer as `--allowed-sid`) besides SYSTEM and
// Administrators. Without that argument the pipe falls back to interactive users,
// which is weaker but keeps a console run usable.
func listenServiceEndpoint(path string) (net.Listener, error) {
	securityDescriptor := "D:(A;;GA;;;SY)(A;;GA;;;BA)(A;;GA;;;IU)"
	if allowedClientSID != "" {
		securityDescriptor = fmt.Sprintf(
			"D:(A;;GA;;;SY)(A;;GA;;;BA)(A;;GA;;;%s)",
			allowedClientSID,
		)
	}
	listener, err := winio.ListenPipe(path, &winio.PipeConfig{
		SecurityDescriptor: securityDescriptor,
		InputBufferSize:    64 * 1024,
		OutputBufferSize:   64 * 1024,
	})
	if err != nil {
		return nil, fmt.Errorf("listen on Clash service pipe: %w", err)
	}
	return listener, nil
}

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
