//go:build darwin || linux

package main

import (
	"errors"
	"fmt"

	"golang.org/x/sys/unix"
)

func closeDesktopTunFD(fd int) error {
	if fd <= 0 {
		return fmt.Errorf("invalid TUN file descriptor: %d", fd)
	}
	if fd <= 2 {
		return errors.New("refusing to close a standard file descriptor")
	}
	return unix.Close(fd)
}
