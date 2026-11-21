//go:build darwin || linux

package main

// desktopAutoRoute is false because the privileged helper owns route setup
// when it hands a TUN descriptor to the core.
const desktopAutoRoute = false
