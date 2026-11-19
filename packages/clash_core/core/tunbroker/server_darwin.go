//go:build darwin

package tunbroker

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/netip"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"golang.org/x/sys/unix"
)

const (
	maxRequestSize  = 1 << 20
	defaultMTU      = 9000
	sysProtoControl = 2
)

type routeEntry struct {
	args []string
}

type server struct {
	socketPath string
	allowedUID uint32
	tunFD      int
	tunName    string
	tunConfig  Config
	routes     []routeEntry
	clientMu   sync.Mutex
	clientFD   int
}

func Serve(ctx context.Context, socketPath string, allowedUID uint32) error {
	listener, err := listen(socketPath)
	if err != nil {
		return err
	}
	defer func() {
		_ = unix.Close(listener)
		_ = os.Remove(socketPath)
	}()

	s := &server{
		socketPath: socketPath,
		allowedUID: allowedUID,
		tunFD:      -1,
		clientFD:   -1,
	}
	defer func() {
		if err := s.deactivate(); err != nil {
			fmt.Fprintln(os.Stderr, err)
		}
	}()
	closed := make(chan struct{})
	go func() {
		select {
		case <-ctx.Done():
			s.closeActiveClient()
		case <-closed:
		}
	}()
	defer close(closed)

	for {
		if ctx.Err() != nil {
			return nil
		}
		pollFDs := []unix.PollFd{{Fd: int32(listener), Events: unix.POLLIN}}
		ready, err := unix.Poll(pollFDs, 500)
		if err != nil {
			if errors.Is(err, unix.EINTR) {
				continue
			}
			return fmt.Errorf("wait for TUN helper connection: %w", err)
		}
		if ready == 0 {
			continue
		}
		if ctx.Err() != nil {
			return nil
		}
		clientFD, _, err := unix.Accept(listener)
		if err != nil {
			return fmt.Errorf("accept TUN helper connection: %w", err)
		}
		s.setActiveClient(clientFD)
		s.handle(clientFD)
		s.clearActiveClient(clientFD)
	}
}

func (s *server) setActiveClient(fd int) {
	s.clientMu.Lock()
	s.clientFD = fd
	s.clientMu.Unlock()
}

func (s *server) clearActiveClient(fd int) {
	s.clientMu.Lock()
	if s.clientFD == fd {
		s.clientFD = -1
	}
	s.clientMu.Unlock()
}

func (s *server) closeActiveClient() {
	s.clientMu.Lock()
	defer s.clientMu.Unlock()
	if s.clientFD >= 0 {
		_ = unix.Shutdown(s.clientFD, unix.SHUT_RDWR)
		_ = unix.Close(s.clientFD)
		s.clientFD = -1
	}
}

func listen(socketPath string) (int, error) {
	if socketPath != SocketPath {
		return -1, fmt.Errorf("refusing unexpected TUN helper socket path %q", socketPath)
	}
	if info, err := os.Lstat(socketPath); err == nil {
		if info.Mode()&os.ModeSocket == 0 {
			return -1, fmt.Errorf("TUN helper path exists and is not a socket: %s", socketPath)
		}
		stat, ok := info.Sys().(*syscall.Stat_t)
		if !ok || stat.Uid != 0 {
			return -1, fmt.Errorf("stale TUN helper socket is not root-owned: %s", socketPath)
		}
		if err := os.Remove(socketPath); err != nil {
			return -1, fmt.Errorf("remove stale TUN helper socket: %w", err)
		}
	} else if !os.IsNotExist(err) {
		return -1, fmt.Errorf("inspect TUN helper socket: %w", err)
	}

	fd, err := unix.Socket(unix.AF_UNIX, unix.SOCK_STREAM, 0)
	if err != nil {
		return -1, fmt.Errorf("create TUN helper listener: %w", err)
	}
	if err := unix.Bind(fd, &unix.SockaddrUnix{Name: socketPath}); err != nil {
		_ = unix.Close(fd)
		return -1, fmt.Errorf("bind TUN helper socket: %w", err)
	}
	if err := os.Chmod(socketPath, 0o666); err != nil {
		_ = unix.Close(fd)
		_ = os.Remove(socketPath)
		return -1, fmt.Errorf("set TUN helper socket permissions: %w", err)
	}
	if err := unix.Listen(fd, 16); err != nil {
		_ = unix.Close(fd)
		_ = os.Remove(socketPath)
		return -1, fmt.Errorf("listen on TUN helper socket: %w", err)
	}
	return fd, nil
}

func (s *server) handle(clientFD int) {
	defer unix.Close(clientFD)
	timeout := unix.NsecToTimeval((10 * time.Second).Nanoseconds())
	if err := unix.SetsockoptTimeval(clientFD, unix.SOL_SOCKET, unix.SO_RCVTIMEO, &timeout); err != nil {
		return
	}

	uid, err := PeerUID(clientFD)
	if err != nil {
		s.respond(clientFD, Response{Error: err.Error()}, -1)
		return
	}
	if uid != s.allowedUID {
		s.respond(clientFD, Response{Error: "caller is not the installed Clashy user"}, -1)
		return
	}

	request, err := readRequest(clientFD)
	if err != nil {
		s.respond(clientFD, Response{Error: err.Error()}, -1)
		return
	}

	switch request.Command {
	case "acquire":
		name, err := s.acquire(request.Config)
		if err != nil {
			s.respond(clientFD, Response{Error: err.Error()}, -1)
			return
		}
		if err := unix.SetsockoptTimeval(clientFD, unix.SOL_SOCKET, unix.SO_RCVTIMEO, &unix.Timeval{}); err != nil {
			cleanupErr := s.deactivate()
			s.respond(clientFD, Response{Error: errors.Join(
				fmt.Errorf("disable TUN helper lease timeout: %w", err),
				cleanupErr,
			).Error()}, -1)
			return
		}
		s.respond(clientFD, Response{Interface: name}, s.tunFD)
		s.awaitLease(clientFD)
	case "deactivate":
		if err := s.deactivate(); err != nil {
			s.respond(clientFD, Response{Error: err.Error()}, -1)
			return
		}
		s.respond(clientFD, Response{}, -1)
	default:
		s.respond(clientFD, Response{Error: "unsupported TUN helper command"}, -1)
	}
}

func (s *server) awaitLease(fd int) {
	request, err := readRequest(fd)
	if err != nil {
		if !errors.Is(err, io.EOF) && !errors.Is(err, unix.EBADF) {
			fmt.Fprintf(os.Stderr, "read TUN helper lease: %v\n", err)
		}
		if cleanupErr := s.deactivate(); cleanupErr != nil {
			fmt.Fprintf(os.Stderr, "release TUN after lease ended: %v\n", cleanupErr)
		}
		return
	}
	if request.Command != "deactivate" {
		s.respond(fd, Response{Error: "unsupported TUN helper lease command"}, -1)
		if cleanupErr := s.deactivate(); cleanupErr != nil {
			fmt.Fprintf(os.Stderr, "release TUN after invalid lease command: %v\n", cleanupErr)
		}
		return
	}
	if err := s.deactivate(); err != nil {
		s.respond(fd, Response{Error: err.Error()}, -1)
		return
	}
	s.respond(fd, Response{}, -1)
}

func readRequest(fd int) (Request, error) {
	line := make([]byte, 0, 4096)
	buffer := make([]byte, 4096)
	for len(line) <= maxRequestSize {
		n, err := unix.Read(fd, buffer)
		if n > 0 {
			chunk := buffer[:n]
			if end := bytes.IndexByte(chunk, '\n'); end >= 0 {
				line = append(line, chunk[:end]...)
				break
			}
			line = append(line, chunk...)
		}
		if err != nil {
			return Request{}, fmt.Errorf("read TUN helper request: %w", err)
		}
		if n == 0 {
			return Request{}, io.EOF
		}
	}
	if len(line) > maxRequestSize {
		return Request{}, errors.New("TUN helper request is too large")
	}
	var request Request
	if err := json.Unmarshal(line, &request); err != nil {
		return Request{}, fmt.Errorf("decode TUN helper request: %w", err)
	}
	return request, nil
}

func (s *server) respond(fd int, response Response, descriptor int) {
	payload, err := json.Marshal(response)
	if err != nil {
		payload = []byte(`{"error":"encode helper response failed"}`)
		descriptor = -1
	}
	payload = append(payload, '\n')
	var rights []byte
	if descriptor >= 0 {
		rights = unix.UnixRights(descriptor)
	}
	if _, err := unix.SendmsgN(fd, payload, rights, nil, 0); err != nil {
		fmt.Fprintf(os.Stderr, "send TUN helper response: %v\n", err)
	}
}

func (s *server) acquire(config Config) (string, error) {
	if err := s.deactivateRoutes(); err != nil {
		return "", err
	}
	if err := validateConfig(config); err != nil {
		return "", err
	}

	if s.tunFD >= 0 &&
		sameInterfaceConfig(s.tunConfig, config) &&
		!interfaceIsUp(s.tunName) {
		if err := configureInterface(s.tunName, config); err != nil {
			if closeErr := s.closeTun(); closeErr != nil {
				return "", errors.Join(err, closeErr)
			}
		}
	}
	if s.tunFD < 0 || !sameInterfaceConfig(s.tunConfig, config) {
		if err := s.closeTun(); err != nil {
			return "", err
		}
		fd, name, err := createTun(config)
		if err != nil {
			return "", err
		}
		s.tunFD = fd
		s.tunName = name
		s.tunConfig = config
	}

	routes, err := RoutePrefixes(config)
	if err != nil {
		return "", err
	}
	if config.AutoRoute {
		if err := s.activateRoutes(routes, config.Bypass); err != nil {
			return "", errors.Join(err, s.closeTun())
		}
	}
	return s.tunName, nil
}

func validateConfig(config Config) error {
	if config.MTU != 0 && (config.MTU < 1280 || config.MTU > 65535) {
		return fmt.Errorf("invalid TUN MTU: %d", config.MTU)
	}
	if len(config.Bypass) > 1024 {
		return errors.New("too many TUN bypass addresses")
	}
	for _, address := range config.Bypass {
		ip, err := netip.ParseAddr(address)
		if err != nil {
			return fmt.Errorf("invalid TUN bypass address %q: %w", address, err)
		}
		if ip.Zone() != "" {
			return fmt.Errorf("scoped TUN bypass address is unsupported: %q", address)
		}
	}
	if len(config.Inet4Address) == 0 && len(config.Inet6Address) == 0 {
		return errors.New("TUN helper requires at least one interface address")
	}
	for _, value := range config.Inet4Address {
		prefix, err := netip.ParsePrefix(value)
		if err != nil || !prefix.Addr().Is4() {
			return fmt.Errorf("invalid TUN IPv4 address %q", value)
		}
	}
	for _, value := range config.Inet6Address {
		prefix, err := netip.ParsePrefix(value)
		if err != nil || !prefix.Addr().Is6() {
			return fmt.Errorf("invalid TUN IPv6 address %q", value)
		}
	}
	if _, err := RoutePrefixes(config); err != nil {
		return err
	}
	if config.AutoRoute && !config.AutoDetectInterface && len(config.Bypass) == 0 {
		return errors.New("automatic TUN routing requires at least one resolved bypass endpoint")
	}
	return nil
}

func sameInterfaceConfig(left, right Config) bool {
	if left.MTU != right.MTU ||
		len(left.Inet4Address) != len(right.Inet4Address) ||
		len(left.Inet6Address) != len(right.Inet6Address) {
		return false
	}
	for i := range left.Inet4Address {
		if left.Inet4Address[i] != right.Inet4Address[i] {
			return false
		}
	}
	for i := range left.Inet6Address {
		if left.Inet6Address[i] != right.Inet6Address[i] {
			return false
		}
	}
	return true
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

func (s *server) activateRoutes(routes, bypass []string) error {
	if err := s.applyRoutes(routes, bypass); err != nil {
		cleanupErr := s.deactivateRoutes()
		return errors.Join(err, cleanupErr)
	}
	return nil
}

func (s *server) applyRoutes(routes, bypass []string) error {
	for _, address := range bypass {
		ip, _ := netip.ParseAddr(address)
		gateway, interfaceName, err := routeFor(ip)
		if err != nil {
			return fmt.Errorf("find physical route for TUN bypass %s: %w", ip, err)
		}
		family := "-inet"
		if ip.Is6() {
			family = "-inet6"
		}
		args := []string{"-n", "add", family, "-host", ip.String()}
		if gatewayIP, parseErr := netip.ParseAddr(gateway); parseErr == nil {
			args = append(args, gatewayIP.String())
		} else if interfaceName != "" {
			args = append(args, "-interface", interfaceName)
		} else {
			return fmt.Errorf("no usable physical route found for TUN bypass %s", ip)
		}
		if err := s.addRoute(args); err != nil {
			return fmt.Errorf("add TUN bypass route for %s: %w", ip, err)
		}
	}
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
		if err := s.addRoute(args); err != nil {
			return fmt.Errorf("add TUN route %s: %w", prefix, err)
		}
	}
	return nil
}

func (s *server) addRoute(args []string) error {
	err := run("/sbin/route", args...)
	if err == nil {
		s.routes = append(s.routes, routeEntry{args: args})
		return nil
	}
	if strings.Contains(err.Error(), "File exists") {
		return nil
	}
	return err
}

func (s *server) deactivateRoutes() error {
	var errs []error
	var remaining []routeEntry
	for index := len(s.routes) - 1; index >= 0; index-- {
		entry := s.routes[index]
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
	s.routes = remaining
	return errors.Join(errs...)
}

func (s *server) deactivate() error {
	return errors.Join(s.deactivateRoutes(), s.closeTun())
}

func routeFor(address netip.Addr) (gateway, interfaceName string, err error) {
	output, err := commandOutput("/sbin/route", "-n", "get", address.String())
	if err != nil {
		return "", "", err
	}
	for _, line := range strings.Split(output, "\n") {
		key, value, ok := strings.Cut(strings.TrimSpace(line), ":")
		if !ok {
			continue
		}
		switch strings.TrimSpace(key) {
		case "gateway":
			gateway = strings.TrimSpace(value)
		case "interface":
			interfaceName = strings.TrimSpace(value)
		}
	}
	if gateway == "" && interfaceName == "" {
		return "", "", errors.New("route lookup returned no gateway or interface")
	}
	return gateway, interfaceName, nil
}

func (s *server) closeTun() error {
	if s.tunFD < 0 {
		return nil
	}
	fd := s.tunFD
	s.tunFD = -1
	s.tunName = ""
	s.tunConfig = Config{}
	err := unix.Close(fd)
	if err != nil {
		return fmt.Errorf("close utun descriptor: %w", err)
	}
	return nil
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
