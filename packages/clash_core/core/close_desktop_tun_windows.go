//go:build windows

package main

func closeDesktopTunFD(int) error {
	return nil
}
