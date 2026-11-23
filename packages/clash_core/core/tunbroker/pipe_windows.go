//go:build windows

package tunbroker

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"syscall"
	"unsafe"

	"golang.org/x/sys/windows"
)

type pipeConn struct {
	handle windows.Handle
}

func newPipeConn(handle windows.Handle) *pipeConn {
	return &pipeConn{handle: handle}
}

func (c *pipeConn) Read(buffer []byte) (int, error) {
	if len(buffer) == 0 {
		return 0, nil
	}
	var read uint32
	err := windows.ReadFile(c.handle, buffer, &read, nil)
	if err != nil {
		return int(read), err
	}
	if read == 0 {
		return 0, io.EOF
	}
	return int(read), nil
}

func (c *pipeConn) Write(payload []byte) (int, error) {
	total := len(payload)
	var written uint32
	for len(payload) > 0 {
		chunk := payload
		if len(chunk) > 64*1024 {
			chunk = chunk[:64*1024]
		}
		if err := windows.WriteFile(c.handle, chunk, &written, nil); err != nil {
			return 0, err
		}
		if written == 0 {
			return 0, errors.New("TUN helper pipe write made no progress")
		}
		payload = payload[written:]
	}
	return total, nil
}

func (c *pipeConn) Close() error {
	return windows.CloseHandle(c.handle)
}

func createPipe() (windows.Handle, error) {
	name, err := windows.UTF16PtrFromString(PipePath)
	if err != nil {
		return 0, err
	}
	handle, err := windows.CreateNamedPipe(
		name,
		windows.PIPE_ACCESS_DUPLEX,
		windows.PIPE_TYPE_BYTE|windows.PIPE_READMODE_BYTE|windows.PIPE_WAIT,
		windows.PIPE_UNLIMITED_INSTANCES,
		64*1024,
		64*1024,
		0,
		nil,
	)
	if err != nil {
		return 0, err
	}
	return handle, nil
}

func createListenPipe() (windows.Handle, error) {
	name, err := windows.UTF16PtrFromString(PipePath)
	if err != nil {
		return 0, err
	}
	securityDescriptor, err := windows.SecurityDescriptorFromString(
		"D:(A;;GA;;;SY)(A;;GA;;;BA)(A;;GA;;;BU)",
	)
	if err != nil {
		return 0, fmt.Errorf("create TUN helper pipe security descriptor: %w", err)
	}
	securityAttributes := &windows.SecurityAttributes{
		Length:             uint32(unsafe.Sizeof(windows.SecurityAttributes{})),
		SecurityDescriptor: securityDescriptor,
	}
	handle, err := windows.CreateNamedPipe(
		name,
		windows.PIPE_ACCESS_DUPLEX,
		windows.PIPE_TYPE_BYTE|windows.PIPE_READMODE_BYTE|windows.PIPE_NOWAIT,
		windows.PIPE_UNLIMITED_INSTANCES,
		64*1024,
		64*1024,
		0,
		securityAttributes,
	)
	runtime.KeepAlive(securityDescriptor)
	if err != nil {
		return 0, err
	}
	return handle, nil
}

func openPipe() (windows.Handle, error) {
	name, err := windows.UTF16PtrFromString(PipePath)
	if err != nil {
		return 0, err
	}
	handle, err := windows.CreateFile(
		name,
		windows.GENERIC_READ|windows.GENERIC_WRITE,
		0,
		nil,
		windows.OPEN_EXISTING,
		0,
		0,
	)
	if err != nil {
		return 0, err
	}
	return handle, nil
}

func pipeClientIsClashy(handle windows.Handle) (bool, error) {
	var processID uint32
	if err := windows.GetNamedPipeClientProcessId(handle, &processID); err != nil {
		return false, err
	}
	process, err := windows.OpenProcess(windows.PROCESS_QUERY_LIMITED_INFORMATION, false, processID)
	if err != nil {
		return false, err
	}
	defer windows.CloseHandle(process)

	var image [windows.MAX_PATH]uint16
	imageSize := uint32(len(image))
	queryFullProcessImageName := syscall.NewLazyDLL("kernel32.dll").NewProc("QueryFullProcessImageNameW")
	result, _, callErr := queryFullProcessImageName.Call(
		uintptr(process),
		0,
		uintptr(unsafe.Pointer(&image[0])),
		uintptr(unsafe.Pointer(&imageSize)),
	)
	if result == 0 {
		return false, callErr
	}
	clientPath := syscall.UTF16ToString(image[:imageSize])
	helperPath, err := os.Executable()
	if err != nil {
		return false, err
	}
	appDir := filepath.Dir(helperPath)
	expectedPaths := []string{
		filepath.Join(appDir, "clashy.exe"),
		filepath.Join(appDir, "clashyservice.exe"),
		filepath.Join(appDir, "data", "flutter_assets", "packages", "clash_service", "bin", "clashyservice.exe"),
	}
	for _, expectedPath := range expectedPaths {
		if strings.EqualFold(filepath.Clean(clientPath), filepath.Clean(expectedPath)) {
			return true, nil
		}
	}
	return false, nil
}
