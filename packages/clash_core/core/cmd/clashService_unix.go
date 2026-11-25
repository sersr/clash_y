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
)

// listenServiceEndpoint binds the control API to the Unix domain socket.
//
// The socket stays world-connectable because the app runs as a regular desktop
// user while the daemon runs as root, but every accepted connection is checked
// against allowedClientUID: the control API drives a privileged process, so any
// other local user must be turned away at accept time instead of being trusted
// to the HTTP layer.
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
	if allowedClientUID >= 0 {
		logf("restricting the Clash service socket to uid %d", allowedClientUID)
		return &uidCheckedListener{Listener: listener}, nil
	}
	return listener, nil
}

// uidCheckedListener drops connections from users that do not own the
// installation. Root is always allowed (an administrator debugging the daemon
// through the socket must not be locked out).
type uidCheckedListener struct {
	net.Listener
}

func (l *uidCheckedListener) Accept() (net.Conn, error) {
	for {
		conn, err := l.Listener.Accept()
		if err != nil {
			return nil, err
		}
		uid, ok := socketPeerUID(conn)
		if ok && (uid == 0 || uid == uint32(allowedClientUID)) {
			return conn, nil
		}
		logf("rejected Clash service connection from uid %d", uid)
		_ = conn.Close()
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
