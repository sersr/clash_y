//go:build windows

package tunbroker

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"os"
	"syscall"
	"time"

	"golang.org/x/sys/windows"
)

func Serve(ctx context.Context, _ string, _ uint32) error {
	handle, err := createListenPipe()
	if err != nil {
		return fmt.Errorf("create TUN helper pipe: %w", err)
	}
	defer windows.CloseHandle(handle)

	for ctx.Err() == nil {
		err := windows.ConnectNamedPipe(handle, nil)
		switch err {
		case nil, windows.ERROR_PIPE_CONNECTED:
			servePipeClient(handle)
			_ = windows.DisconnectNamedPipe(handle)
		case windows.ERROR_NO_DATA:
			time.Sleep(200 * time.Millisecond)
		default:
			return fmt.Errorf("accept TUN helper connection: %w", err)
		}
	}
	return nil
}

func servePipeClient(handle windows.Handle) {
	defer func() {
		if err := deactivateTun(); err != nil {
			fmt.Fprintln(os.Stderr, err)
		}
	}()

	elevated, err := pipeClientIsElevated(handle)
	if err != nil || !elevated {
		writePipeResponse(handle, Response{Error: "caller is not an elevated Clashy service"})
		return
	}

	conn := newPipeConn(handle)
	reader := bufio.NewReader(conn)
	request, err := readRequest(reader)
	if err != nil {
		writePipeResponse(handle, Response{Error: err.Error()})
		return
	}

	switch request.Command {
	case "acquire":
		name, err := acquireTun(request.Config)
		if err != nil {
			writePipeResponse(handle, Response{Error: err.Error()})
			return
		}
		writePipeResponse(handle, Response{Interface: name})
		awaitWindowsLease(reader, handle)
	case "deactivate":
		if err := deactivateTun(); err != nil {
			writePipeResponse(handle, Response{Error: err.Error()})
			return
		}
		writePipeResponse(handle, Response{})
	default:
		writePipeResponse(handle, Response{Error: "unsupported TUN helper command"})
	}
}

func awaitWindowsLease(reader *bufio.Reader, handle windows.Handle) {
	request, err := readRequest(reader)
	if err != nil {
		if !errors.Is(err, os.ErrClosed) && !errors.Is(err, syscall.Errno(109)) {
			fmt.Fprintf(os.Stderr, "read TUN helper lease: %v\n", err)
		}
		return
	}
	if request.Command != "deactivate" {
		writePipeResponse(handle, Response{Error: "unsupported TUN helper lease command"})
		return
	}
	if err := deactivateTun(); err != nil {
		writePipeResponse(handle, Response{Error: err.Error()})
		return
	}
	writePipeResponse(handle, Response{})
}

func writePipeResponse(handle windows.Handle, response Response) {
	if err := writeResponse(readerWriter{conn: newPipeConn(handle)}, response); err != nil {
		fmt.Fprintf(os.Stderr, "send TUN helper response: %v\n", err)
	}
}
