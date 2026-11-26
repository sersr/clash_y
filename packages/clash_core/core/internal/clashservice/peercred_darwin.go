//go:build darwin

package clashservice

import (
	"net"

	"golang.org/x/sys/unix"
)

// socketPeerUID reports the uid that opened the other end of a Unix socket
// connection through LOCAL_PEERCRED, which is macOS' equivalent of SO_PEERCRED.
func socketPeerUID(conn net.Conn) (uint32, bool) {
	unixConn, ok := conn.(*net.UnixConn)
	if !ok {
		return 0, false
	}
	raw, err := unixConn.SyscallConn()
	if err != nil {
		return 0, false
	}

	var uid uint32
	var okFlag bool
	if err := raw.Control(func(fd uintptr) {
		xucred, credErr := unix.GetsockoptXucred(int(fd), unix.SOL_LOCAL, unix.LOCAL_PEERCRED)
		if credErr != nil {
			return
		}
		uid = xucred.Uid
		okFlag = true
	}); err != nil {
		return 0, false
	}
	return uid, okFlag
}
