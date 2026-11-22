//go:build linux

package tunbroker

import (
	"errors"
	"fmt"
	"net"
	"net/netip"
	"os"
	"strings"
	"unsafe"

	"github.com/sagernet/netlink"
	"golang.org/x/sys/unix"
)

const linuxTunPath = "/dev/net/tun"

type linuxRoute struct {
	route *netlink.Route
}

func createTun(config Config) (int, string, error) {
	fd, err := unix.Open(linuxTunPath, unix.O_RDWR, 0)
	if err != nil {
		return -1, "", fmt.Errorf("open %s: %w", linuxTunPath, err)
	}
	fail := func(err error) (int, string, error) {
		_ = unix.Close(fd)
		return -1, "", err
	}

	name := InterfaceName
	var ifr struct {
		name  [16]byte
		flags uint16
		_     [22]byte
	}
	copy(ifr.name[:], name)
	ifr.flags = unix.IFF_TUN | unix.IFF_NO_PI
	if _, _, errno := unix.Syscall(
		unix.SYS_IOCTL, uintptr(fd), uintptr(unix.TUNSETIFF), uintptr(unsafe.Pointer(&ifr)),
	); errno != 0 {
		return fail(fmt.Errorf("create TUN interface %s: %w", name, errno))
	}
	if err := unix.SetNonblock(fd, true); err != nil {
		return fail(fmt.Errorf("set TUN non-blocking: %w", err))
	}
	name = string(ifr.name[:])
	if end := strings.IndexByte(name, 0); end >= 0 {
		name = name[:end]
	}
	if err := configureInterface(name, config); err != nil {
		return fail(err)
	}
	return fd, name, nil
}

func configureInterface(name string, config Config) error {
	link, err := netlink.LinkByName(name)
	if err != nil {
		return fmt.Errorf("find TUN interface %s: %w", name, err)
	}
	mtu := config.MTU
	if mtu == 0 {
		mtu = defaultMTU
	}
	if err := netlink.LinkSetMTU(link, int(mtu)); err != nil {
		return fmt.Errorf("set TUN MTU: %w", err)
	}
	for _, value := range config.Inet4Address {
		prefix, _ := netip.ParsePrefix(value)
		if err := netlink.AddrAdd(link, &netlink.Addr{IPNet: ipNet(prefix)}); err != nil &&
			!errors.Is(err, os.ErrExist) {
			return fmt.Errorf("configure TUN IPv4 address %s: %w", value, err)
		}
	}
	for _, value := range config.Inet6Address {
		prefix, _ := netip.ParsePrefix(value)
		if err := netlink.AddrAdd(link, &netlink.Addr{IPNet: ipNet(prefix)}); err != nil &&
			!errors.Is(err, os.ErrExist) {
			return fmt.Errorf("configure TUN IPv6 address %s: %w", value, err)
		}
	}
	if err := netlink.LinkSetUp(link); err != nil {
		return fmt.Errorf("bring TUN interface up: %w", err)
	}
	return nil
}

func interfaceIsUp(name string) bool {
	link, err := netlink.LinkByName(name)
	if err != nil {
		return false
	}
	return link.Attrs().Flags&net.FlagUp != 0
}

func activateRoutes(s *server, routes []string) error {
	if err := applyLinuxRoutes(s, routes); err != nil {
		cleanupErr := deactivateRoutes(s)
		return errors.Join(err, cleanupErr)
	}
	return nil
}

func applyLinuxRoutes(s *server, routes []string) error {
	link, err := netlink.LinkByName(s.tunName)
	if err != nil {
		return fmt.Errorf("find TUN interface %s: %w", s.tunName, err)
	}
	for _, value := range routes {
		prefix, err := netip.ParsePrefix(value)
		if err != nil {
			return fmt.Errorf("invalid TUN route %q: %w", value, err)
		}
		route := &netlink.Route{LinkIndex: link.Attrs().Index, Dst: ipNet(prefix)}
		if err := netlink.RouteAdd(route); err != nil {
			if errors.Is(err, os.ErrExist) || errors.Is(err, unix.EEXIST) {
				continue
			}
			return fmt.Errorf("add TUN route %s: %w", value, err)
		}
		addLinuxRoute(s, route)
	}
	return nil
}

func addLinuxRoute(s *server, route *netlink.Route) {
	if s.platform == nil {
		s.platform = &linuxServerState{}
	}
	state := s.platform.(*linuxServerState)
	state.routes = append(state.routes, linuxRoute{route: route})
}

func deactivateRoutes(s *server) error {
	if s.platform == nil {
		return nil
	}
	state, ok := s.platform.(*linuxServerState)
	if !ok || len(state.routes) == 0 {
		return nil
	}
	var errs []error
	var remaining []linuxRoute
	for index := len(state.routes) - 1; index >= 0; index-- {
		entry := state.routes[index]
		if err := netlink.RouteDel(entry.route); err != nil {
			if errors.Is(err, os.ErrNotExist) || errors.Is(err, unix.ENOENT) {
				continue
			}
			errs = append(errs, err)
			remaining = append(remaining, entry)
		}
	}
	state.routes = remaining
	return errors.Join(errs...)
}

type linuxServerState struct {
	routes []linuxRoute
}

func ipNet(prefix netip.Prefix) *net.IPNet {
	return &net.IPNet{
		IP:   prefix.Addr().AsSlice(),
		Mask: net.CIDRMask(prefix.Bits(), prefix.Addr().BitLen()),
	}
}
