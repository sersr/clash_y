//go:build darwin

package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"regexp"
	"strings"
	"syscall"
)

// runPlatformService is the LaunchDaemon entry point. The daemon runs as root
// (system domain), creates the TUN interface itself, serves the control API and
// stops the core when launchd sends SIGTERM.
//
// The menu bar item is a separate LaunchAgent in the user's GUI session: a
// daemon lives in the system domain, which has no WindowServer connection, so it
// must never try to draw UI itself.
func runPlatformService() {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	done := make(chan error, 1)
	go func() { done <- serve(ctx, nil) }()

	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGTERM)

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
