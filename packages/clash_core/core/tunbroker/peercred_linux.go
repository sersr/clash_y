//go:build linux

package tunbroker

import (
	"fmt"

	"golang.org/x/sys/unix"
)

// peerUID returns the uid of the process on the other end of a Unix socket.
func peerUID(fd int) (uint32, error) {
	credentials, err := unix.GetsockoptUcred(fd, unix.SOL_SOCKET, unix.SO_PEERCRED)
	if err != nil {
		return 0, fmt.Errorf("read TUN helper client credentials: %w", err)
	}
	return credentials.Uid, nil
}
