package tunbroker

import (
	"net/netip"
	"strings"
	"testing"
)

func TestRoutePrefixesUsesSplitDefaultRoutesAndExclusions(t *testing.T) {
	routes, err := RoutePrefixes(Config{
		AutoRoute:    true,
		Inet4Address: []string{"172.19.0.1/30"},
		Inet6Address: []string{"fdfe:dcba:9876::1/126"},
	})
	if err != nil {
		t.Fatal(err)
	}

	for _, route := range routes {
		if route == "172.19.0.0/30" || route == "fdfe:dcba:9876::/126" {
			t.Fatalf("TUN interface route unexpectedly included: %s", route)
		}
	}
	var ipv4Routes []string
	for _, route := range routes {
		if strings.Contains(route, ".") {
			ipv4Routes = append(ipv4Routes, route)
		}
	}
	if len(ipv4Routes) != 8 {
		t.Fatalf("unexpected IPv4 default routes: %v", ipv4Routes)
	}
}

func TestRoutePrefixesSubtractsExclusions(t *testing.T) {
	routes, err := RoutePrefixes(Config{
		AutoRoute:           true,
		RouteAddress:        []string{"10.0.0.0/8"},
		RouteExcludeAddress: []string{"10.1.0.0/16"},
	})
	if err != nil {
		t.Fatal(err)
	}
	excluded := netip.MustParseAddr("10.1.2.3")
	for _, route := range routes {
		prefix := netip.MustParsePrefix(route)
		if prefix.Contains(excluded) {
			t.Fatalf("excluded address is still routed through TUN: %s", route)
		}
	}
}

func TestRoutePrefixesDoesNotCreateRoutesWhenAutoRouteDisabled(t *testing.T) {
	routes, err := RoutePrefixes(Config{
		Inet4Address: []string{"172.19.0.1/30"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if len(routes) != 0 {
		t.Fatalf("expected no routes, got %v", routes)
	}
}

func TestRoutePrefixesRejectsInvalidInput(t *testing.T) {
	_, err := RoutePrefixes(Config{
		AutoRoute:    true,
		RouteAddress: []string{"not-a-prefix"},
	})
	if err == nil {
		t.Fatal("expected invalid route to be rejected")
	}
}
