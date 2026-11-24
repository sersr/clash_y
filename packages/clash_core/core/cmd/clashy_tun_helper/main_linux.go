//go:build linux

package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"mihomo-so/tunbroker"
)

func main() {
	socketPath := flag.String("socket", tunbroker.SocketPath, "privileged helper socket")
	allowedUID := flag.Uint("allowed-uid", 0, "UID permitted to request TUN access")
	flag.Parse()
	if os.Geteuid() != 0 {
		fatal(errors.New("TUN helper must run as root"))
	}
	if *socketPath != tunbroker.SocketPath {
		fatal(fmt.Errorf("unsupported socket path %q", *socketPath))
	}
	// clashyService runs as root on Linux, so the helper accepts root as the
	// only caller. Non-root users must go through clashyService's API.
	if *allowedUID != 0 {
		fatal(fmt.Errorf("unsupported allowed UID %d (must be 0)", *allowedUID))
	}

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer cancel()
	if err := tunbroker.Serve(ctx, *socketPath, uint32(*allowedUID)); err != nil {
		fatal(err)
	}
}

func fatal(err error) {
	if errors.Is(err, context.Canceled) {
		return
	}
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}
