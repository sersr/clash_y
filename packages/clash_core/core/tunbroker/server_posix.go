//go:build darwin || linux

package tunbroker

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"sync"
	"syscall"
	"time"

	"golang.org/x/sys/unix"
)

const defaultMTU = 9000

type server struct {
	socketPath string
	allowedUID uint32
	tunFD      int
	tunName    string
	tunConfig  Config
	clientMu   sync.Mutex
	clientFD   int

	// Platform state (installed routes, adapter handles, ...).
	platform any
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

	s := newServer(socketPath, allowedUID)
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
		if ready == 0 || ctx.Err() != nil {
			continue
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

func newServer(socketPath string, allowedUID uint32) *server {
	return &server{
		socketPath: socketPath,
		allowedUID: allowedUID,
		tunFD:      -1,
		clientFD:   -1,
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

	uid, err := peerUID(clientFD)
	if err != nil {
		s.respond(clientFD, Response{Error: err.Error()}, -1)
		return
	}
	if uid != s.allowedUID {
		s.respond(clientFD, Response{Error: "caller is not the installed Clashy user"}, -1)
		return
	}

	reader := bufio.NewReader(fdReader{fd: clientFD})
	request, err := readRequest(reader)
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
		s.awaitLease(clientFD, reader)
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

func (s *server) awaitLease(fd int, reader *bufio.Reader) {
	request, err := readRequest(reader)
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
	if err := deactivateRoutes(s); err != nil {
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
		if err := activateRoutes(s, routes, config.Bypass); err != nil {
			return "", errors.Join(err, s.closeTun())
		}
	}
	return s.tunName, nil
}

func (s *server) deactivate() error {
	return errors.Join(deactivateRoutes(s), s.closeTun())
}

func (s *server) closeTun() error {
	if s.tunFD < 0 {
		return nil
	}
	fd := s.tunFD
	s.tunFD = -1
	s.tunName = ""
	s.tunConfig = Config{}
	if err := unix.Close(fd); err != nil {
		return fmt.Errorf("close TUN descriptor: %w", err)
	}
	return nil
}

