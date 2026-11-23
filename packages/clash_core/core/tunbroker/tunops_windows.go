//go:build windows

package tunbroker

import (
	"fmt"

	singtun "github.com/metacubex/sing-tun"
)

const defaultMTU = 9000

// Windows helpers provision the Wintun adapter; the core opens the same
// adapter by name afterwards and manages its own packet session and routes.
func acquireTun(config Config) (string, error) {
	if err := validateConfig(config); err != nil {
		return "", err
	}
	if err := deactivateTun(); err != nil {
		return "", err
	}

	options := singtun.Options{
		Name:      InterfaceName,
		MTU:       config.MTU,
		AutoRoute: false,
		DNSMode:   singtun.DNSModeDisabled,
	}
	if options.MTU == 0 {
		options.MTU = defaultMTU
	}
	tun, err := singtun.New(options)
	if err != nil {
		return "", fmt.Errorf("create Wintun adapter: %w", err)
	}
	if err := tun.Close(); err != nil {
		return "", fmt.Errorf("release Wintun adapter: %w", err)
	}
	return InterfaceName, nil
}

func deactivateTun() error {
	return nil
}
