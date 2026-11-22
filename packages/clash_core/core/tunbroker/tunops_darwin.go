//go:build darwin

package tunbroker

import (
	"errors"
	"fmt"
	"net"
	"net/netip"
	"os"
	"os/exec"
	"strconv"
	"strings"

	"golang.org/x/sys/unix"
)

const sysProtoControl = 2

type darwinRoute struct {
	args []string
}

func createTun(config Config) (int, string, error) {
	fd, err := unix.Socket(unix.AF_SYSTEM, unix.SOCK_DGRAM, sysProtoControl)
	if err != nil {
		return -1, "", fmt.Errorf("open utun control socket: %w", err)
	}
	fail := func(err error) (int, string, error) {
		_ = unix.Close(fd)
		return -1, "", err
	}

	control := &unix.CtlInfo{}
	copy(control.Name[:], "com.apple.net.utun_control")
	if err := unix.IoctlCtlInfo(fd, control); err != nil {
		return fail(fmt.Errorf("look up utun control: %w", err))
	}
	if err := unix.Connect(fd, &unix.SockaddrCtl{ID: control.Id, Unit: 0}); err != nil {
		return fail(fmt.Errorf("create utun interface: %w", err))
	}
	name, err := unix.GetsockoptString(fd, sysProtoControl, 2)
	if err != nil {
		return fail(fmt.Errorf("read utun interface name: %w", err))
	}
	if !strings.HasPrefix(name, "utun") {
		return fail(fmt.Errorf("unexpected utun interface name %q", name))
	}
	if err := configureInterface(name, config); err != nil {
		return fail(err)
	}
	return fd, name, nil
}

func configureInterface(name string, config Config) error {
	mtu := config.MTU
	if mtu == 0 {
		mtu = defaultMTU
	}
	if err := run("/sbin/ifconfig", name, "mtu", strconv.FormatUint(uint64(mtu), 10)); err != nil {
		return fmt.Errorf("set TUN MTU: %w", err)
	}
	for _, value := range config.Inet4Address {
		prefix, _ := netip.ParsePrefix(value)
		peer := prefix.Addr().Next()
		if !peer.IsValid() {
			return fmt.Errorf("invalid TUN IPv4 peer for %q", value)
		}
		mask := net.IP(net.CIDRMask(prefix.Bits(), 32)).String()
		if err := run("/sbin/ifconfig", name, "inet", prefix.Addr().String(), peer.String(), "netmask", mask); err != nil {
			return fmt.Errorf("configure TUN IPv4 address %s: %w", value, err)
		}
	}
	for _, value := range config.Inet6Address {
		prefix, _ := netip.ParsePrefix(value)
		args := []string{name, "inet6", prefix.Addr().String(), "prefixlen", strconv.Itoa(prefix.Bits())}
		if err := run("/sbin/ifconfig", args...); err != nil {
			return fmt.Errorf("configure TUN IPv6 address %s: %w", value, err)
		}
	}
	if err := run("/sbin/ifconfig", name, "up"); err != nil {
		return fmt.Errorf("bring TUN interface up: %w", err)
	}
	return nil
}

func interfaceIsUp(name string) bool {
	output, err := commandOutput("/sbin/ifconfig", name)
	if err != nil {
		return false
	}
	firstLine, _, _ := strings.Cut(output, "\n")
	return strings.Contains(firstLine, "<UP")
}

func activateRoutes(s *server, routes []string) error {
	if err := applyDarwinRoutes(s, routes); err != nil {
		cleanupErr := deactivateRoutes(s)
		return errors.Join(err, cleanupErr)
	}
	return nil
}

func applyDarwinRoutes(s *server, routes []string) error {
	for _, prefix := range routes {
		parsed, err := netip.ParsePrefix(prefix)
		if err != nil {
			return fmt.Errorf("invalid TUN route %q: %w", prefix, err)
		}
		family := "-inet"
		if parsed.Addr().Is6() {
			family = "-inet6"
		}
		args := []string{"-n", "add", family, "-net", prefix, "-interface", s.tunName}
		if err := addDarwinRoute(s, args); err != nil {
			return fmt.Errorf("add TUN route %s: %w", prefix, err)
		}
	}
	return nil
}

func addDarwinRoute(s *server, args []string) error {
	err := run("/sbin/route", args...)
	if err == nil {
		state := darwinState(s)
		state.routes = append(state.routes, darwinRoute{args: args})
		return nil
	}
	if strings.Contains(err.Error(), "File exists") {
		return nil
	}
	return err
}

func deactivateRoutes(s *server) error {
	state := darwinState(s)
	var errs []error
	var remaining []darwinRoute
	for index := len(state.routes) - 1; index >= 0; index-- {
		entry := state.routes[index]
		args := append([]string(nil), entry.args...)
		args[1] = "delete"
		if err := run("/sbin/route", args...); err != nil &&
			!strings.Contains(err.Error(), "not in table") {
			errs = append(errs, err)
			remaining = append(remaining, entry)
		}
	}
	for left, right := 0, len(remaining)-1; left < right; left, right = left+1, right-1 {
		remaining[left], remaining[right] = remaining[right], remaining[left]
	}
	state.routes = remaining
	return errors.Join(errs...)
}

func darwinState(s *server) *darwinServerState {
	if s.platform == nil {
		s.platform = &darwinServerState{}
	}
	return s.platform.(*darwinServerState)
}

type darwinServerState struct {
	routes []darwinRoute
}

func run(name string, args ...string) error {
	_, err := commandOutput(name, args...)
	return err
}

func commandOutput(name string, args ...string) (string, error) {
	command := exec.Command(name, args...)
	for _, value := range os.Environ() {
		if !strings.HasPrefix(value, "LC_ALL=") {
			command.Env = append(command.Env, value)
		}
	}
	command.Env = append(command.Env, "LC_ALL=C")
	output, err := command.CombinedOutput()
	if err != nil {
		return "", fmt.Errorf("%s %s: %w: %s", name, strings.Join(args, " "), err, strings.TrimSpace(string(output)))
	}
	return string(output), nil
}
