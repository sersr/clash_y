//go:build darwin || linux

package main

// The helper owns system route setup for its externally created TUN device.
const desktopAutoRoute = false
