//go:build windows

package tunbroker

import (
	"bufio"
	"errors"
	"fmt"
	"sync"
	"syscall"
	"time"
)

var (
	leaseMu     sync.Mutex
	leaseConn   *pipeConn
	leaseReader *bufio.Reader
)

// Acquire asks the privileged helper to provision the TUN adapter. Windows
// hands no descriptor back; the core opens the adapter by name afterwards.
func Acquire(config Config) (int, string, error) {
	leaseMu.Lock()
	defer leaseMu.Unlock()
	if leaseConn != nil {
		if err := deactivateLeaseLocked(); err != nil && !isPipeDisconnected(err) {
			return 0, "", err
		}
	}

	conn, err := dialHelper()
	if err != nil {
		return 0, "", err
	}
	reader := bufio.NewReader(conn)
	if err := writeRequest(readerWriter{conn}, Request{Command: "acquire", Config: config}); err != nil {
		conn.Close()
		return 0, "", fmt.Errorf("send TUN helper request: %w", err)
	}
	response, err := readResponse(reader)
	if err != nil {
		conn.Close()
		return 0, "", fmt.Errorf("read TUN helper response: %w", err)
	}
	if response.Error != "" {
		conn.Close()
		return 0, "", errors.New(response.Error)
	}
	if response.Interface == "" {
		conn.Close()
		return 0, "", errors.New("TUN helper returned no interface name")
	}
	leaseConn = conn
	leaseReader = reader
	return 0, response.Interface, nil
}

func isPipeDisconnected(err error) bool {
	return errors.Is(err, syscall.Errno(109)) || // ERROR_BROKEN_PIPE
		errors.Is(err, syscall.Errno(232)) || // ERROR_NO_DATA
		errors.Is(err, syscall.Errno(233)) // ERROR_PIPE_NOT_CONNECTED
}

// Activate is a no-op because the Windows core installs its own routes.
func Activate() error { return nil }

// Deactivate releases the current TUN lease.
func Deactivate() error {
	leaseMu.Lock()
	defer leaseMu.Unlock()
	if leaseConn != nil {
		return deactivateLeaseLocked()
	}

	conn, err := dialHelper()
	if err != nil {
		return err
	}
	defer conn.Close()
	if err := writeRequest(readerWriter{conn}, Request{Command: "deactivate"}); err != nil {
		return fmt.Errorf("send TUN helper request: %w", err)
	}
	response, err := readResponse(bufio.NewReader(conn))
	if err != nil {
		return fmt.Errorf("read TUN helper response: %w", err)
	}
	if response.Error != "" {
		return errors.New(response.Error)
	}
	return nil
}

func deactivateLeaseLocked() error {
	conn := leaseConn
	reader := leaseReader
	leaseConn = nil
	leaseReader = nil
	defer conn.Close()

	if err := writeRequest(readerWriter{conn}, Request{Command: "deactivate"}); err != nil {
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

func dialHelper() (*pipeConn, error) {
	deadline := time.Now().Add(10 * time.Second)
	var lastErr error
	for {
		handle, err := openPipe()
		if err == nil {
			return newPipeConn(handle), nil
		}
		lastErr = err
		if time.Now().After(deadline) {
			return nil, fmt.Errorf("connect to TUN helper: %w", lastErr)
		}
		time.Sleep(100 * time.Millisecond)
	}
}

type readerWriter struct {
	conn *pipeConn
}

func (w readerWriter) Write(payload []byte) (int, error) {
	return w.conn.Write(payload)
}
