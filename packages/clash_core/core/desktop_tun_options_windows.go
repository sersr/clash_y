//go:build windows

package main

// On Windows the helper only provisions the Wintun adapter; the core runs
// privileged and configures routes itself.
const desktopAutoRoute = true
