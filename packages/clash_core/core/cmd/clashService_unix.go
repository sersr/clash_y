//go:build darwin || linux

package main

import (
	"errors"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"golang.org/x/sys/unix"
)

// socketReadyTimeout bounds how long the daemon waits for a privileged TUN
// helper to start accepting requests.
const socketReadyTimeout = 10 * time.Second

// listenServiceEndpoint binds the control API to the Unix domain socket. The
// socket is world-writable because the app runs as a regular desktop user while
// the daemon runs as root or as a LaunchAgent of that user.
func listenServiceEndpoint(path string) (net.Listener, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, fmt.Errorf("create Clash service socket directory: %w", err)
	}
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		return nil, fmt.Errorf("remove stale Clash service socket: %w", err)
	}

	listener, err := net.Listen("unix", path)
	if err != nil {
		return nil, fmt.Errorf("listen on Clash service socket: %w", err)
	}
	if err := os.Chmod(path, 0o666); err != nil {
		listener.Close()
		return nil, fmt.Errorf("allow desktop apps to reach the Clash service socket: %w", err)
	}
	return listener, nil
}

// closeFileDescriptor releases a TUN descriptor handed over by the helper.
func closeFileDescriptor(fd int) error {
	if fd <= 2 {
		return fmt.Errorf("refusing to close a standard file descriptor: %d", fd)
	}
	return unix.Close(fd)
}

// waitUntilUnixSocketReady blocks until a privileged TUN helper accepts
// connections on its Unix socket, or the timeout expires.
func waitUntilUnixSocketReady(path string, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	var lastErr error
	for {
		conn, err := net.DialTimeout("unix", path, 2*time.Second)
		if err == nil {
			_ = conn.Close()
			return nil
		}
		lastErr = err
		if time.Now().After(deadline) {
			return fmt.Errorf("TUN helper socket is not ready: %s (%v)", path, lastErr)
		}
		time.Sleep(100 * time.Millisecond)
	}
}

// execExitError keeps the exit code of a failed command so the caller can
// distinguish "the script failed" from "the script could not be started".
type execExitError struct {
	code   int
	output string
	err    error
}

func (e *execExitError) Error() string {
	if e.output == "" {
		return e.err.Error()
	}
	return fmt.Sprintf("%v: %s", e.err, e.output)
}

func (e *execExitError) Unwrap() error { return e.err }

// commandOutput runs a command and returns its combined output. A non-zero exit
// code is reported as *execExitError so callers can react to the code itself.
func commandOutput(path string, args ...string) (string, error) {
	output, err := exec.Command(path, args...).CombinedOutput()
	trimmed := strings.TrimSpace(string(output))
	if err != nil {
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) {
			return trimmed, &execExitError{code: exitErr.ExitCode(), output: trimmed, err: err}
		}
		return trimmed, err
	}
	return trimmed, nil
}

func shellQuote(value string) string {
	return "'" + strings.ReplaceAll(value, "'", `'\''`) + "'"
}
