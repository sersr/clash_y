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
	if *allowedUID == 0 {
		fatal(errors.New("TUN helper requires a non-root allowed UID"))
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
