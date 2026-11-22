//go:build darwin || linux || windows

package main

import (
	"fmt"
	"runtime"

	"github.com/metacubex/mihomo/config"
	"mihomo-so/tunbroker"
)

// acquireDesktopTun asks the platform's privileged helper to create the TUN
// interface. On Unix the helper also passes the file descriptor back; on
// Windows it only provisions the adapter and the core opens it by name.
func acquireDesktopTun(cfg *config.Config) (int, string, error) {
	tunConfig, err := desktopTunConfig(cfg)
	if err != nil {
		return -1, "", err
	}
	fd, interfaceName, err := tunbroker.Acquire(tunConfig)
	if err != nil {
		return -1, "", err
	}
	return fd, interfaceName, nil
}

func activateDesktopTun() error {
	if runtime.GOOS == "windows" {
		return nil
	}
	return tunbroker.Activate()
}

func deactivateDesktopTun() error {
	return tunbroker.Deactivate()
}

func desktopTunConfig(cfg *config.Config) (tunbroker.Config, error) {
	tun := cfg.General.Tun
	if len(tun.RouteAddressSet) > 0 || len(tun.RouteExcludeAddressSet) > 0 {
		return tunbroker.Config{}, fmt.Errorf("TUN helper does not support route-address-set yet")
	}

	options := tunbroker.Config{
		MTU:       tun.MTU,
		AutoRoute: tun.AutoRoute,
	}
	for _, address := range tun.Inet4Address {
		options.Inet4Address = append(options.Inet4Address, address.String())
	}
	for _, address := range tun.Inet6Address {
		options.Inet6Address = append(options.Inet6Address, address.String())
	}
	if len(options.Inet4Address) == 0 {
		options.Inet4Address = []string{"172.19.0.1/30"}
	}
	if len(options.Inet6Address) == 0 {
		options.Inet6Address = []string{"fdfe:dcba:9876::1/126"}
	}
	for _, address := range tun.RouteAddress {
		options.RouteAddress = append(options.RouteAddress, address.String())
	}
	for _, address := range tun.Inet4RouteAddress {
		options.RouteAddress = append(options.RouteAddress, address.String())
	}
	for _, address := range tun.Inet6RouteAddress {
		options.RouteAddress = append(options.RouteAddress, address.String())
	}
	for _, address := range tun.RouteExcludeAddress {
		options.RouteExcludeAddress = append(options.RouteExcludeAddress, address.String())
	}
	for _, address := range tun.Inet4RouteExcludeAddress {
		options.RouteExcludeAddress = append(options.RouteExcludeAddress, address.String())
	}
	for _, address := range tun.Inet6RouteExcludeAddress {
		options.RouteExcludeAddress = append(options.RouteExcludeAddress, address.String())
	}

	return options, nil
}
