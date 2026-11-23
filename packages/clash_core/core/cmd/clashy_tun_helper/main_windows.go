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

	"golang.org/x/sys/windows/svc"
	"mihomo-so/tunbroker"
)

const serviceName = "clashy_tun_helper"

func main() {
	pipe := flag.String("pipe", tunbroker.PipePath, "privileged helper pipe")
	flag.Parse()
	if *pipe != tunbroker.PipePath {
		fatal(fmt.Errorf("unsupported pipe path %q", *pipe))
	}
	service, err := svc.IsWindowsService()
	if err != nil {
		fatal(err)
	}
	if service {
		if err := svc.Run(serviceName, windowsService{pipe: *pipe}); err != nil {
			fatal(err)
		}
		return
	}

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer cancel()
	if err := tunbroker.Serve(ctx, *pipe, 0); err != nil {
		fatal(err)
	}
}

type windowsService struct{ pipe string }

func (s windowsService) Execute(
	_ []string,
	requests <-chan svc.ChangeRequest,
	changes chan<- svc.Status,
) (bool, uint32) {
	changes <- svc.Status{State: svc.StartPending}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	ready := make(chan struct{})
	done := make(chan error, 1)
	go func() { done <- tunbroker.ServeWithReady(ctx, s.pipe, 0, ready) }()

	select {
	case <-ready:
		changes <- svc.Status{
			State:   svc.Running,
			Accepts: svc.AcceptStop | svc.AcceptShutdown,
		}
	case err := <-done:
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return true, 1
		}
		return false, 0
	}

	for {
		select {
		case change := <-requests:
			switch change.Cmd {
			case svc.Interrogate:
				changes <- change.CurrentStatus
			case svc.Stop, svc.Shutdown:
				changes <- svc.Status{State: svc.StopPending}
				cancel()
				if err := <-done; err != nil && !errors.Is(err, context.Canceled) {
					fmt.Fprintln(os.Stderr, err)
					return true, 1
				}
				return false, 0
			}
		case err := <-done:
			if err != nil {
				fmt.Fprintln(os.Stderr, err)
				return true, 1
			}
			return false, 0
		}
	}
}

func fatal(err error) {
	if errors.Is(err, context.Canceled) {
		return
	}
	fmt.Fprintln(os.Stderr, err)
	os.Exit(1)
}
