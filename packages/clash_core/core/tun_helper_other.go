//go:build !darwin

package main

import (
	"errors"

	"github.com/metacubex/mihomo/config"
)

func acquireMacOSTun(*config.Config) (int, error) {
	return -1, errors.New("macOS TUN helper is unavailable on this platform")
}

func deactivateMacOSTun() error {
	return nil
}

func closeMacOSTunFD(int) error {
	return nil
}
