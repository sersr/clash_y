//go:build linux

package main

import (
	"net"

	"golang.org/x/sys/unix"
)

// socketPeerUID reports the uid that opened the other end of a Unix socket
// connection, using the kernel-provided peer credentials.
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
		cred, credErr := unix.GetsockoptUcred(int(fd), unix.SOL_SOCKET, unix.SO_PEERCRED)
		if credErr != nil {
			return
		}
		uid = cred.Uid
		okFlag = true
	}); err != nil {
		return 0, false
	}
	return uid, okFlag
}
