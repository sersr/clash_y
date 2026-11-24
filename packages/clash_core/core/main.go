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
	configDirG := C.GoString(configDir)

	enableEmbeddedConfigUpdates()
	return startMobile(configDirG)
}

func isDesktopOS() bool {
	switch runtime.GOOS {
	case "darwin", "linux", "windows":
		return true
	default:
		return false
	}
}

func startMobile(configDir string) *C.char {
	if !started {
		resetMobileTunListener()
	}

	if err := setHomeDir(configDir); err != nil {
		return cError(err)
	}

	if err := hub.Parse(nil); err != nil {
		return cError(fmt.Errorf("start core: %w", err))
	}

	started = true
	return nil
}

func startDesktop(configDir string) {
	// Tear down an earlier TUN listener before applying the config again. This
	// matters on Windows where start() lets mihomo create the Wintun adapter
	// directly from config.yaml.
	// if err := resetDesktopTunListener(); err != nil {
	// 	return cError(err)
	// }
	if started {
		executor.Shutdown()
		started = false
	}

	if err := setHomeDir(configDir); err != nil {
		return
	}

	if err := hub.Parse(nil); err != nil {
		return
	}

	started = true
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

//export startDesktopTun
func startDesktopTun(configDir *C.char, vpnEnabled C.int) {
	config := C.GoString(configDir)
	vpn := vpnEnabled != 0
	startDesktopTunI(config, vpn)
}

func startDesktopTunI(configDir string, vpnEnabled bool) {
	mu.Lock()
	defer mu.Unlock()

	if err := setHomeDir(configDir); err != nil {
		return
	}

	cfg, err := executor.Parse()
	if err != nil {
		return
	}

	if err := resetDesktopTunListener(); err != nil {
		return
	}
	if started {
		executor.Shutdown()
		started = false
	}
	hub.ApplyConfig(cfg)
	return

	if runtime.GOOS == "windows" {
		cfg.General.Tun.Enable = vpnEnabled
		return
	}

	// The input value is a request: 0 means core-only, -1 asks the desktop
	// helper for TUN, and a positive value is a real inherited descriptor.
	tunRequested := vpnEnabled
	tunFD := 0
	var tunInterface string
	if vpnEnabled {
		tunFD, tunInterface, err = acquireDesktopTun(cfg)
		if err != nil {
			return
		}
		tunBrokerActive = true
	}

	cfg.General.Tun.Enable = false
	hub.ApplyConfig(cfg)

	if !tunRequested {
		started = true
		return
	}

	// POSIX helpers return a real descriptor. Windows provisions Wintun by
	// name, so its helper returns fd=0 and a non-empty interface name instead.
	tunFDUsable := tunFD > 0
	tunDeviceUsable := runtime.GOOS == "windows" && tunInterface != ""
	if !tunFDUsable && !tunDeviceUsable {
		if tunBrokerActive {
			_ = deactivateDesktopTun()
			tunBrokerActive = false
		}
		return
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
		return
	}
	if tunBrokerActive {
		if err := activateDesktopTun(); err != nil {
			_ = listener.Close()
			cleanupErr := deactivateDesktopTun()
			if cleanupErr == nil {
				tunBrokerActive = false
			}
			executor.Shutdown()
			return
		}
	}

	tunListener = listener
	started = true
	return
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

// stopTun disables only the desktop TUN listener. Keep the core process and
// its initialized runtime alive so a later start() can apply the config again.
// Android uses stop(), which also shuts down the complete core.
//
//export stopTun
func stopTun() *C.char {
	mu.Lock()
	defer mu.Unlock()

	return stopMobileTun()
}

func stopMobileTun() *C.char {
	resetMobileTunListener()
	tunnel.OnSuspend()
	started = false
	return nil
}

//export stopDesktopTun
func stopDesktopTun() {
	mu.Lock()
	defer mu.Unlock()

	if err := resetDesktopTunListener(); err != nil {
		return
	}
	tunnel.OnSuspend()
	started = false
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

// 指令类型
const (
	cmdStart = iota
	cmdStop
)

type command struct {
	typ       int
	configDir string
	vpn       bool
}

var (
	cmdCh   = make(chan command, 4)
	running bool
)

//export startW
func startW(configDir *C.char, vpnEnabled C.int) C.int {
	cfg := C.GoString(configDir)
	select {
	case cmdCh <- command{typ: cmdStart, configDir: cfg, vpn: vpnEnabled != 0}:
		return 0
	default:
		return -1 // 队列满
	}

}

//export stopW
func stopW() C.int {
	select {
	case cmdCh <- command{typ: cmdStop}:
		return 0
	default:
		return -1
	}
}

//export runLoop
func runLoop() {

	for cmd := range cmdCh {
		switch cmd.typ {
		case cmdStart:
			startDesktopTunI(cmd.configDir, cmd.vpn)
		case cmdStop:
			stopDesktopTun()
		}
	}
}
