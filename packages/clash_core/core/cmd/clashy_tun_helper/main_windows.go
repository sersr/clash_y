//go:build windows

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
	pipe := flag.String("pipe", tunbroker.PipePath, "privileged helper pipe")
	flag.Parse()
	if *pipe != tunbroker.PipePath {
		fatal(fmt.Errorf("unsupported pipe path %q", *pipe))
	}

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer cancel()
	if err := tunbroker.Serve(ctx, *pipe, 0); err != nil {
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
