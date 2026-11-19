//go:build darwin

package tunbroker

import (
	"errors"
	"testing"

	"golang.org/x/sys/unix"
)

func TestDeactivateClosesTunDescriptor(t *testing.T) {
	descriptors := make([]int, 2)
	if err := unix.Pipe(descriptors); err != nil {
		t.Fatalf("create test pipe: %v", err)
	}
	defer unix.Close(descriptors[1])

	s := testServerWithTunFD(descriptors[0])
	if err := s.deactivate(); err != nil {
		t.Fatalf("deactivate TUN: %v", err)
	}
	assertTunClosed(t, s, descriptors[0])
}

func TestLeaseEndClosesTunDescriptor(t *testing.T) {
	tunDescriptors := make([]int, 2)
	if err := unix.Pipe(tunDescriptors); err != nil {
		t.Fatalf("create TUN test pipe: %v", err)
	}
	defer unix.Close(tunDescriptors[1])

	leaseDescriptors := make([]int, 2)
	if err := unix.Pipe(leaseDescriptors); err != nil {
		t.Fatalf("create lease test pipe: %v", err)
	}
	defer unix.Close(leaseDescriptors[0])
	if err := unix.Close(leaseDescriptors[1]); err != nil {
		t.Fatalf("close lease writer: %v", err)
	}

	s := testServerWithTunFD(tunDescriptors[0])
	s.awaitLease(leaseDescriptors[0])
	assertTunClosed(t, s, tunDescriptors[0])
}

func testServerWithTunFD(fd int) *server {
	return &server{
		tunFD:     fd,
		tunName:   "utun7",
		tunConfig: Config{MTU: 1400},
	}
}

func assertTunClosed(t *testing.T, s *server, fd int) {
	t.Helper()
	if s.tunFD != -1 ||
		s.tunName != "" ||
		s.tunConfig.MTU != 0 ||
		len(s.tunConfig.Inet4Address) != 0 ||
		len(s.tunConfig.Inet6Address) != 0 {
		t.Fatalf("TUN state was not cleared: %+v", s)
	}
	if _, err := unix.FcntlInt(uintptr(fd), unix.F_GETFD, 0); !errors.Is(err, unix.EBADF) {
		t.Fatalf("TUN descriptor is still open; F_GETFD error = %v", err)
	}
}
