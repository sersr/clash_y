//go:build darwin

package main

import (
	"errors"
	"fmt"
	"net"
	"net/netip"
	"net/url"
	"strings"

	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/dns"
	"golang.org/x/sys/unix"
	"mihomo-so/tunbroker"
)

func acquireMacOSTun(cfg *config.Config) (int, error) {
	tunConfig, err := macOSTunConfig(cfg)
	if err != nil {
		return -1, err
	}
	fd, _, err := tunbroker.Acquire(tunConfig)
	if err != nil {
		return -1, err
	}
	return fd, nil
}

func deactivateMacOSTun() error {
	return tunbroker.Deactivate()
}

func closeMacOSTunFD(fd int) error {
	if fd <= 0 {
		return errors.New("invalid macOS TUN file descriptor")
	}
	return unix.Close(fd)
}

func macOSTunConfig(cfg *config.Config) (tunbroker.Config, error) {
	tun := cfg.General.Tun
	if len(tun.RouteAddressSet) > 0 || len(tun.RouteExcludeAddressSet) > 0 {
		return tunbroker.Config{}, fmt.Errorf("macOS TUN helper does not support route-address-set yet")
	}

	options := tunbroker.Config{
		MTU:                 tun.MTU,
		AutoRoute:           tun.AutoRoute,
		AutoDetectInterface: true,
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

	endpoints := make(map[string]struct{})
	for _, proxy := range cfg.Proxies {
		if err := addEndpoint(endpoints, proxy.Addr()); err != nil {
			return tunbroker.Config{}, err
		}
	}
	if cfg.DNS != nil {
		for _, servers := range [][]dns.NameServer{
			cfg.DNS.NameServer,
			cfg.DNS.Fallback,
			cfg.DNS.DefaultNameserver,
			cfg.DNS.ProxyServerNameserver,
			cfg.DNS.DirectNameServer,
		} {
			for _, server := range servers {
				if err := addEndpoint(endpoints, server.Addr); err != nil {
					return tunbroker.Config{}, err
				}
			}
		}
	}
	for endpoint := range endpoints {
		options.Bypass = append(options.Bypass, endpoint)
	}
	return options, nil
}

func addEndpoint(endpoints map[string]struct{}, address string) error {
	if address == "" {
		return nil
	}
	host := address
	if strings.Contains(address, "://") {
		parsed, err := url.Parse(address)
		if err != nil {
			return fmt.Errorf("parse TUN bypass endpoint %q: %w", address, err)
		}
		host = parsed.Hostname()
	} else if splitHost, _, err := net.SplitHostPort(address); err == nil {
		host = splitHost
	} else if parsed, err := netip.ParseAddr(strings.Trim(address, "[]")); err == nil {
		host = parsed.String()
	}
	host = strings.Trim(host, "[]")
	if ip, err := netip.ParseAddr(host); err == nil {
		endpoints[ip.String()] = struct{}{}
		return nil
	}
	if host == "" {
		return nil
	}
	addresses, err := net.LookupIP(host)
	if err != nil {
		return fmt.Errorf("resolve TUN bypass endpoint %q: %w", host, err)
	}
	for _, address := range addresses {
		ip, ok := netip.AddrFromSlice(address)
		if ok {
			endpoints[ip.Unmap().String()] = struct{}{}
		}
	}
	return nil
}
