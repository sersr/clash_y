//go:build darwin || linux

package tunbroker

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"sync"
	"time"

	"golang.org/x/sys/unix"
)

var (
	leaseMu     sync.Mutex
	leaseFD     = -1
	leaseReader *bufio.Reader
)

// Acquire asks the privileged helper for a TUN descriptor. The returned
// descriptor stays valid until Deactivate is called.
func Acquire(config Config) (int, string, error) {
	leaseMu.Lock()
	defer leaseMu.Unlock()
	if leaseFD >= 0 {
		if err := deactivateLeaseLocked(); err != nil {
			return -1, "", err
		}
	}

	response, tunFD, connectionFD, err := send(Request{Command: "acquire", Config: config}, true)
	if err != nil {
		return -1, "", err
	}
	if response.Error != "" {
		if tunFD >= 0 {
			_ = unix.Close(tunFD)
		}
		_ = unix.Close(connectionFD)
		return -1, "", errors.New(response.Error)
	}
	if tunFD < 0 {
		_ = unix.Close(connectionFD)
		return -1, "", errors.New("TUN helper returned no file descriptor")
	}
	if response.Interface == "" {
		_ = unix.Close(tunFD)
		_ = unix.Close(connectionFD)
		return -1, "", errors.New("TUN helper returned no interface name")
	}
	leaseFD = connectionFD
	leaseReader = bufio.NewReader(fdReader{fd: connectionFD})
	return tunFD, response.Interface, nil
}

// Activate applies routes from the configuration used to acquire the lease.
func Activate() error {
	leaseMu.Lock()
	defer leaseMu.Unlock()
	if leaseFD < 0 {
		return errors.New("TUN helper lease is not active")
	}
	if err := writeRequest(fdWriter{fd: leaseFD}, Request{Command: "activate"}); err != nil {
		return fmt.Errorf("activate TUN helper routes: %w", err)
	}
	response, err := readResponse(leaseReader)
	if err != nil {
		return fmt.Errorf("read TUN helper activation response: %w", err)
	}
	if response.Error != "" {
		return errors.New(response.Error)
	}
	return nil
}

// Deactivate releases the current TUN lease and asks the helper to clean up.
func Deactivate() error {
	leaseMu.Lock()
	defer leaseMu.Unlock()
	if leaseFD >= 0 {
		return deactivateLeaseLocked()
	}

	response, _, connectionFD, err := send(Request{Command: "deactivate"}, false)
	if connectionFD >= 0 {
		_ = unix.Close(connectionFD)
	}
	if err != nil {
		return err
	}
	if response.Error != "" {
		return errors.New(response.Error)
	}
	return nil
}

func deactivateLeaseLocked() error {
	fd := leaseFD
	reader := leaseReader
	leaseFD = -1
	leaseReader = nil
	defer unix.Close(fd)

	if err := writeRequest(fdWriter{fd: fd}, Request{Command: "deactivate"}); err != nil {
		return fmt.Errorf("deactivate TUN helper lease: %w", err)
	}
	response, err := readResponse(reader)
	if err != nil {
		return fmt.Errorf("read TUN helper lease response: %w", err)
	}
	if response.Error != "" {
		return errors.New(response.Error)
	}
	return nil
}

type fdWriter struct{ fd int }

func (w fdWriter) Write(payload []byte) (int, error) {
	return unix.Write(w.fd, payload)
}

type fdReader struct{ fd int }

func (r fdReader) Read(buffer []byte) (int, error) {
	n, err := unix.Read(r.fd, buffer)
	if err != nil {
		return n, err
	}
	if n == 0 {
		return 0, errors.New("TUN helper closed the lease")
	}
	return n, nil
}

func send(request Request, expectDescriptor bool) (Response, int, int, error) {
	fd, err := unix.Socket(unix.AF_UNIX, unix.SOCK_STREAM, 0)
	if err != nil {
		return Response{}, -1, -1, fmt.Errorf("create TUN helper socket: %w", err)
	}
	receivedFD := -1
	fail := func(err error) (Response, int, int, error) {
		if receivedFD >= 0 {
			_ = unix.Close(receivedFD)
		}
		_ = unix.Close(fd)
		return Response{}, -1, -1, err
	}

	timeout := unix.NsecToTimeval((15 * time.Second).Nanoseconds())
	if err := unix.SetsockoptTimeval(fd, unix.SOL_SOCKET, unix.SO_RCVTIMEO, &timeout); err != nil {
		return fail(fmt.Errorf("set TUN helper receive timeout: %w", err))
	}
	if err := unix.SetsockoptTimeval(fd, unix.SOL_SOCKET, unix.SO_SNDTIMEO, &timeout); err != nil {
		return fail(fmt.Errorf("set TUN helper send timeout: %w", err))
	}
	if err := unix.Connect(fd, &unix.SockaddrUnix{Name: SocketPath}); err != nil {
		return fail(fmt.Errorf("connect to TUN helper: %w", err))
	}

	if err := writeRequest(fdWriter{fd: fd}, request); err != nil {
		return fail(fmt.Errorf("send TUN helper request: %w", err))
	}

	oob := make([]byte, unix.CmsgSpace(4))
	var data []byte
	buffer := make([]byte, 4096)
	for len(data) <= maxMessageSize {
		n, oobn, flags, _, err := unix.Recvmsg(fd, buffer, oob, 0)
		if err != nil {
			return fail(fmt.Errorf("receive TUN helper response: %w", err))
		}
		if flags&unix.MSG_CTRUNC != 0 {
			return fail(errors.New("TUN helper file descriptor data was truncated"))
		}
		if oobn > 0 {
			messages, err := unix.ParseSocketControlMessage(oob[:oobn])
			if err != nil {
				return fail(fmt.Errorf("parse TUN helper file descriptor: %w", err))
			}
			for _, message := range messages {
				rights, err := unix.ParseUnixRights(&message)
				if err != nil {
					continue
				}
				if len(rights) > 0 {
					if receivedFD < 0 {
						receivedFD = rights[0]
						rights = rights[1:]
					}
					for _, extra := range rights {
						_ = unix.Close(extra)
					}
				}
			}
		}
		if n > 0 {
			data = append(data, buffer[:n]...)
			if bytes.Contains(data, []byte{'\n'}) {
				break
			}
		}
		if n == 0 {
			return fail(errors.New("TUN helper closed before completing its response"))
		}
	}

	if len(data) > maxMessageSize {
		return fail(errors.New("TUN helper response is too large"))
	}
	if newline := bytes.IndexByte(data, '\n'); newline >= 0 {
		data = data[:newline]
	}
	var response Response
	if err := json.Unmarshal(data, &response); err != nil {
		return fail(fmt.Errorf("decode TUN helper response: %w", err))
	}

	if expectDescriptor && receivedFD < 0 && response.Error == "" {
		return fail(errors.New("TUN helper response did not contain a file descriptor"))
	}
	if receivedFD >= 0 {
		if _, err := unix.FcntlInt(uintptr(receivedFD), unix.F_SETFD, unix.FD_CLOEXEC); err != nil {
			return fail(fmt.Errorf("protect TUN file descriptor: %w", err))
		}
	}

	return response, receivedFD, fd, nil
}
