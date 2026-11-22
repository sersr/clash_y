// Command clash_core exposes github.com/metacubex/mihomo as a C shared library.
//
// Build (Android):
//
//	CGO_ENABLED=1 GOOS=android GOARCH=arm64 CC=".../clang --target=aarch64-linux-android21" \
//	go build -buildmode=c-shared -trimpath -tags with_gvisor,cmfa -o libclash.so .
//
// The cmfa tag is required on Android: it makes sing-tun adopt the file
// descriptor of the app's VpnService instead of creating and routing its own
// tun device.
//
// Build (host, for local debugging):
//
//	go build -buildmode=c-shared -tags with_gvisor -o libclash.dylib .
//
// Exported C API - every function returns NULL on success, otherwise a newly
// allocated message that the caller must release with freeString():
//
//	char *start(const char *configDir);
//	char *startTun(const char *configDir, int fd);
//	char *stop(void);
//	void  freeString(char *s);
//
// mihomo does not export its internal startTun helper, but the listener level
// entry point it uses (listener.ReCreateTun) is public, so no patched mihomo
// build is required.
package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"errors"
	"fmt"
	"net/netip"
	"path/filepath"
	"runtime"
	"sync"
	"unsafe"

	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/hub/route"
	"github.com/metacubex/mihomo/listener"
	LC "github.com/metacubex/mihomo/listener/config"
	"github.com/metacubex/mihomo/listener/sing_tun"
	"github.com/metacubex/mihomo/tunnel"
)

// configFileName is the file mihomo reads from the -d home directory.
const configFileName = "config.yaml"

var (
	mu              sync.Mutex
	started         bool
	tunListener     *sing_tun.Listener
	tunBrokerActive bool
)

// main is required by -buildmode=c-shared and never runs.
func main() {}

// start boots the core with the configuration found in configDir, mirroring
// `mihomo -d configDir`. TUN follows whatever the config file declares.
//
//export start
func start(configDir *C.char) *C.char {
	mu.Lock()
	defer mu.Unlock()

	enableEmbeddedConfigUpdates()
	if isDesktopOS() {
		return startDesktop(configDir)
	}
	return startMobile(configDir)
}

func isDesktopOS() bool {
	switch runtime.GOOS {
	case "darwin", "linux", "windows":
		return true
	default:
		return false
	}
}

func startMobile(configDir *C.char) *C.char {
	if !started {
		resetMobileTunListener()
	}

	if err := setHomeDir(C.GoString(configDir)); err != nil {
		return cError(err)
	}

	if err := hub.Parse(nil); err != nil {
		return cError(fmt.Errorf("start core: %w", err))
	}

	started = true
	return nil
}

func startDesktop(configDir *C.char) *C.char {
	if !started {
		if err := resetDesktopTunListener(); err != nil {
			return cError(err)
		}
	}

	if err := setHomeDir(C.GoString(configDir)); err != nil {
		return cError(err)
	}

	if err := hub.Parse(nil); err != nil {
		return cError(fmt.Errorf("start core: %w", err))
	}

	started = true
	return nil
}

// startTun starts the core with TUN enabled when given a TUN descriptor.
// A positive fd is an externally established descriptor, supplied by Android's
// VpnService. On macOS, -1 asks the privileged helper for a descriptor. A zero
// fd starts the core with TUN disabled.
//
// Every call re-reads configDir/config.yaml and applies the full mihomo
// configuration, so ports, proxies, rules, controller and TUN are always
// up-to-date. The supplied fd is owned by mihomo after a successful call.
//
//export startTun
func startTun(configDir *C.char, fd C.int) *C.char {
	mu.Lock()
	defer mu.Unlock()

	enableEmbeddedConfigUpdates()
	if isDesktopOS() {
		return startDesktopTun(configDir, int(fd))
	}
	return startMobileTun(configDir, int(fd))
}

func startMobileTun(configDir *C.char, fd int) *C.char {
	if err := setHomeDir(C.GoString(configDir)); err != nil {
		return cError(err)
	}

	cfg, err := executor.Parse()
	if err != nil {
		return cError(fmt.Errorf("parse config: %w", err))
	}

	if fd > 0 && (cfg.Controller == nil || cfg.Controller.ExternalControllerUnix == "") {
		return cError(errors.New("external-controller-unix is not configured in config.yaml; configDir may not have been loaded"))
	}

	if tunListener != nil {
		_ = tunListener.Close()
		tunListener = nil
	}
	if started {
		executor.Shutdown()
		started = false
	}

	// Let mihomo apply the complete config except TUN. TUN is created below
	// directly through sing_tun.New, so the externally established interface
	// remains under the mobile VPN service's control.
	cfg.General.Tun.Enable = false
	hub.ApplyConfig(cfg)

	if fd <= 0 {
		started = true
		return nil
	}

	options := buildFdTunOptions(cfg, fd, runtime.GOOS)
	listener, err := sing_tun.New(options, tunnel.Tunnel)
	if err != nil {
		executor.Shutdown()
		return cError(fmt.Errorf("start tun: %w", err))
	}
	tunListener = listener
	started = true
	return nil
}

func startDesktopTun(configDir *C.char, fd int) *C.char {
	if err := setHomeDir(C.GoString(configDir)); err != nil {
		return cError(err)
	}

	cfg, err := executor.Parse()
	if err != nil {
		return cError(fmt.Errorf("parse config: %w", err))
	}

	if fd != 0 && (cfg.Controller == nil || cfg.Controller.ExternalControllerUnix == "") {
		return cError(errors.New("external-controller-unix is not configured in config.yaml; configDir may not have been loaded"))
	}

	if err := resetDesktopTunListener(); err != nil {
		return cError(err)
	}
	if started {
		executor.Shutdown()
		started = false
	}

	tunFD := fd
	var tunInterface string
	if tunFD == -1 {
		tunFD, tunInterface, err = acquireDesktopTun(cfg)
		if err != nil {
			return cError(fmt.Errorf("acquire TUN helper: %w", err))
		}
		tunBrokerActive = true
	}

	cfg.General.Tun.Enable = false
	hub.ApplyConfig(cfg)

	if tunFD <= 0 {
		started = true
		return nil
	}

	options := buildDesktopFdTunOptions(cfg, tunFD, tunInterface)
	listener, err := sing_tun.New(options, tunnel.Tunnel)
	if err != nil {
		_ = closeDesktopTunFD(tunFD)
		if tunBrokerActive {
			if deactivateErr := deactivateDesktopTun(); deactivateErr != nil {
				err = errors.Join(err, deactivateErr)
			} else {
				tunBrokerActive = false
			}
		}
		executor.Shutdown()
		return cError(fmt.Errorf("start tun: %w", err))
	}
	if tunBrokerActive {
		if err := activateDesktopTun(); err != nil {
			closeErr := listener.Close()
			cleanupErr := deactivateDesktopTun()
			if cleanupErr == nil {
				tunBrokerActive = false
			}
			executor.Shutdown()
			return cError(errors.Join(fmt.Errorf("activate TUN routes: %w", err), closeErr, cleanupErr))
		}
	}

	tunListener = listener
	started = true
	return nil
}

func buildFdTunOptions(cfg *config.Config, fd int, goos string) LC.Tun {
	stack := cfg.General.Tun.Stack
	if stack.String() == "unknown" {
		stack = constant.TunGvisor
	}

	dnsHijack := []string{"172.19.0.2:53"}
	mtu := uint32(9000)
	if goos == "ios" {
		mtu = 1500
	}

	device := cfg.General.Tun.Device
	if device == "" {
		device = "clashy"
	}

	autoDetectInterface := cfg.General.Tun.AutoDetectInterface
	if goos == "android" {
		autoDetectInterface = false
	}

	return LC.Tun{
		Enable:              true,
		Device:              device,
		Stack:               stack,
		DNSHijack:           dnsHijack,
		AutoRoute:           false,
		AutoDetectInterface: autoDetectInterface,
		Inet4Address: []netip.Prefix{
			netip.MustParsePrefix("172.19.0.1/30"),
		},
		Inet6Address: []netip.Prefix{
			netip.MustParsePrefix("fdfe:dcba:9876::1/126"),
		},
		MTU:            mtu,
		FileDescriptor: fd,
	}
}

func buildDesktopFdTunOptions(cfg *config.Config, fd int, helperInterface string) LC.Tun {
	stack := cfg.General.Tun.Stack
	if stack.String() == "unknown" {
		stack = constant.TunGvisor
	}

	mtu := cfg.General.Tun.MTU
	if mtu == 0 {
		mtu = 9000
	}
	device := helperInterface
	if device == "" {
		device = cfg.General.Tun.Device
	}
	if device == "" {
		device = "clashy"
	}

	inet4Address := cfg.General.Tun.Inet4Address
	if len(inet4Address) == 0 {
		inet4Address = []netip.Prefix{
			netip.MustParsePrefix("172.19.0.1/30"),
		}
	}
	inet6Address := cfg.General.Tun.Inet6Address
	if len(inet6Address) == 0 {
		inet6Address = []netip.Prefix{
			netip.MustParsePrefix("fdfe:dcba:9876::1/126"),
		}
	}

	return LC.Tun{
		Enable:                   true,
		Device:                   device,
		Stack:                    stack,
		DNSHijack:                []string{"172.19.0.2:53"},
		AutoRoute:                desktopAutoRoute,
		AutoDetectInterface:      true,
		Inet4Address:             inet4Address,
		Inet6Address:             inet6Address,
		RouteAddress:             cfg.General.Tun.RouteAddress,
		Inet4RouteAddress:        cfg.General.Tun.Inet4RouteAddress,
		Inet6RouteAddress:        cfg.General.Tun.Inet6RouteAddress,
		RouteExcludeAddress:      cfg.General.Tun.RouteExcludeAddress,
		Inet4RouteExcludeAddress: cfg.General.Tun.Inet4RouteExcludeAddress,
		Inet6RouteExcludeAddress: cfg.General.Tun.Inet6RouteExcludeAddress,
		MTU:                      mtu,
		FileDescriptor:           fd,
	}
}

// stop shuts the core down and closes every listener, including TUN.
//
//export stop
func stop() *C.char {
	mu.Lock()
	defer mu.Unlock()

	if isDesktopOS() {
		return stopDesktop()
	}
	return stopMobile()
}

func stopMobile() *C.char {
	if tunListener != nil {
		_ = tunListener.Close()
		tunListener = nil
	}
	if started {
		executor.Shutdown()
		started = false
	}

	listener.Cleanup()
	started = false
	return nil
}

func stopDesktop() *C.char {
	resetErr := resetDesktopTunListener()
	if started {
		executor.Shutdown()
		started = false
	}

	listener.Cleanup()
	started = false
	if resetErr != nil {
		return cError(resetErr)
	}
	return nil
}

// stopTun disables only the desktop TUN listener. Keep the core process and
// its initialized runtime alive so a later start() can apply the config again.
// Android uses stop(), which also shuts down the complete core.
//
//export stopTun
func stopTun() *C.char {
	mu.Lock()
	defer mu.Unlock()

	if isDesktopOS() {
		return stopDesktopTun()
	}
	return stopMobileTun()
}

func stopMobileTun() *C.char {
	resetMobileTunListener()
	tunnel.OnSuspend()
	started = false
	return nil
}

func stopDesktopTun() *C.char {
	if err := resetDesktopTunListener(); err != nil {
		return cError(err)
	}
	tunnel.OnSuspend()
	started = false
	return nil
}

func resetMobileTunListener() {
	listener.ReCreateTun(LC.Tun{}, tunnel.Tunnel)
}

func resetDesktopTunListener() error {
	var errs []error
	// Stop Mihomo's readers and packet-processing stack before releasing the
	// helper lease that owns the underlying TUN device.
	if tunListener != nil {
		if err := tunListener.Close(); err != nil {
			errs = append(errs, err)
		}
		tunListener = nil
	}
	if tunBrokerActive {
		if err := deactivateDesktopTun(); err != nil {
			errs = append(errs, err)
		} else {
			tunBrokerActive = false
		}
	}
	// ReCreateTun clears mihomo's cached TUN configuration.
	listener.ReCreateTun(LC.Tun{}, tunnel.Tunnel)
	return errors.Join(errs...)
}

// freeString releases a string returned by this library.
//
//export freeString
func freeString(s *C.char) {
	if s == nil {
		return
	}
	C.free(unsafe.Pointer(s))
}

// enableEmbeddedConfigUpdates re-enables the REST config update endpoints that
// mihomo disables by default on Android (cmfa). The Android client keeps the
// current TUN file descriptor in the config it sends to PUT /configs, so the
// listener sees an unchanged TUN configuration and does not recreate/close it.
func enableEmbeddedConfigUpdates() {
	route.SetEmbedMode(false)
}

// setHomeDir points mihomo at configDir and prepares config.yaml, the same way
// the CLI does for its -d flag.
func setHomeDir(configDir string) error {
	if configDir == "" {
		return errors.New("config dir is empty")
	}

	abs, err := filepath.Abs(configDir)
	if err != nil {
		return fmt.Errorf("resolve config dir: %w", err)
	}

	constant.SetHomeDir(abs)
	constant.SetConfig(filepath.Join(abs, configFileName))

	if err := config.Init(abs); err != nil {
		return fmt.Errorf("init config dir: %w", err)
	}

	return nil
}

// cError converts a Go error into a heap allocated C string.
func cError(err error) *C.char {
	if err == nil {
		return nil
	}
	return C.CString(err.Error())
}
