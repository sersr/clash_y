package tunbroker

import (
	"fmt"
	"net/netip"
	"slices"

	"go4.org/netipx"
)

const (
	// SocketPath is the Unix domain socket used by the macOS and Linux helpers.
	SocketPath = "/var/run/clashy-tun-helper.sock"
	// PipePath is the named pipe used by the Windows helper.
	PipePath = `\\.\pipe\clashy\tun_helper.pipe`
	// InterfaceName is the TUN device name shared by every helper.
	InterfaceName = "clashy"
)

type Config struct {
	MTU                 uint32   `json:"mtu"`
	Inet4Address        []string `json:"inet4Address"`
	Inet6Address        []string `json:"inet6Address"`
	AutoRoute           bool     `json:"autoRoute"`
	RouteAddress        []string `json:"routeAddress"`
	RouteExcludeAddress []string `json:"routeExcludeAddress"`
}

type Request struct {
	Command string `json:"command"`
	Config  Config `json:"config,omitempty"`
}

type Response struct {
	Error     string `json:"error,omitempty"`
	Interface string `json:"interface,omitempty"`
}

func RoutePrefixes(config Config) ([]string, error) {
	if !config.AutoRoute {
		return nil, nil
	}

	var ipv4, ipv6 []netip.Prefix
	for _, value := range config.RouteAddress {
		prefix, err := netip.ParsePrefix(value)
		if err != nil {
			return nil, fmt.Errorf("invalid TUN route address %q: %w", value, err)
		}
		if prefix.Addr().Is4() {
			ipv4 = append(ipv4, prefix)
		} else {
			ipv6 = append(ipv6, prefix)
		}
	}
	var exclude4, exclude6 []netip.Prefix
	for _, value := range config.RouteExcludeAddress {
		prefix, err := netip.ParsePrefix(value)
		if err != nil {
			return nil, fmt.Errorf("invalid TUN excluded route %q: %w", value, err)
		}
		if prefix.Addr().Is4() {
			exclude4 = append(exclude4, prefix)
		} else {
			exclude6 = append(exclude6, prefix)
		}
	}

	var address4, address6 []netip.Prefix
	for _, value := range config.Inet4Address {
		prefix, err := netip.ParsePrefix(value)
		if err != nil || !prefix.Addr().Is4() {
			return nil, fmt.Errorf("invalid TUN IPv4 address %q", value)
		}
		address4 = append(address4, prefix)
	}
	for _, value := range config.Inet6Address {
		prefix, err := netip.ParsePrefix(value)
		if err != nil || !prefix.Addr().Is6() {
			return nil, fmt.Errorf("invalid TUN IPv6 address %q", value)
		}
		address6 = append(address6, prefix)
	}

	if len(ipv4) == 0 && len(address4) > 0 {
		ipv4 = defaultIPv4Routes()
	}
	if len(ipv6) == 0 && len(address6) > 0 {
		ipv6 = defaultIPv6Routes()
	}

	routes4, err := subtractRoutes(ipv4, address4, exclude4)
	if err != nil {
		return nil, err
	}
	routes6, err := subtractRoutes(ipv6, address6, exclude6)
	if err != nil {
		return nil, err
	}

	routes := append(routes4, routes6...)
	slices.Sort(routes)
	return routes, nil
}

func subtractRoutes(routes, addresses, excludes []netip.Prefix) ([]string, error) {
	var builder netipx.IPSetBuilder
	for _, route := range routes {
		builder.AddPrefix(route)
	}
	for _, address := range addresses {
		if address.Bits() < address.Addr().BitLen() {
			builder.AddPrefix(address.Masked())
		}
	}
	for _, exclude := range excludes {
		builder.RemovePrefix(exclude)
	}

	set, err := builder.IPSet()
	if err != nil {
		return nil, fmt.Errorf("build TUN route set: %w", err)
	}
	prefixes := set.Prefixes()
	result := make([]string, len(prefixes))
	for index, prefix := range prefixes {
		result[index] = prefix.String()
	}
	return result, nil
}

func defaultIPv4Routes() []netip.Prefix {
	return []netip.Prefix{
		netip.MustParsePrefix("1.0.0.0/8"),
		netip.MustParsePrefix("2.0.0.0/7"),
		netip.MustParsePrefix("4.0.0.0/6"),
		netip.MustParsePrefix("8.0.0.0/5"),
		netip.MustParsePrefix("16.0.0.0/4"),
		netip.MustParsePrefix("32.0.0.0/3"),
		netip.MustParsePrefix("64.0.0.0/2"),
		netip.MustParsePrefix("128.0.0.0/1"),
	}
}

func defaultIPv6Routes() []netip.Prefix {
	return []netip.Prefix{
		netip.MustParsePrefix("100::/8"),
		netip.MustParsePrefix("200::/7"),
		netip.MustParsePrefix("400::/6"),
		netip.MustParsePrefix("800::/5"),
		netip.MustParsePrefix("1000::/4"),
		netip.MustParsePrefix("2000::/3"),
		netip.MustParsePrefix("4000::/2"),
		netip.MustParsePrefix("8000::/1"),
	}
}
