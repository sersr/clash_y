//go:build linux

package main

import (
	"context"
	"os"
	"os/signal"
	"regexp"
	"syscall"
)

// runPlatformService is the systemd entry point. The unit runs as root, so the
// daemon creates the TUN interface itself. Both SIGTERM and SIGINT stop the core
// before exiting so no TUN device or route is left behind.
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

// listTunInterfaces has no macOS-style kernel-assigned TUN name to track: the
// interface uses the fixed defaultTunDevice name.
func listTunInterfaces() ([]string, error) { return nil, nil }

// tunInterfaceHealthy reports whether the TUN device is still up.
func tunInterfaceHealthy(iface string) bool {
	output, err := commandOutput("ip", "link", "show", iface)
	if err != nil {
		return false
	}
	return regexp.MustCompile(`\bUP\b`).MatchString(output)
}
