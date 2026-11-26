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
//	char *prepare(const char *configDir);
//	char *refreshProfile(const char *configDir, const char *url, const char *script);
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

	"mihomo-so/internal/geoensure"
	"mihomo-so/internal/profilerefresh"
)

// configFileName is the file mihomo reads from the -d home directory.
const configFileName = "config.yaml"

var (
	mu          sync.Mutex
	started     bool
	tunListener *sing_tun.Listener
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
	if !started {
		resetTunListener()
	}

	if err := setHomeDir(C.GoString(configDir)); err != nil {
		return cError(err)
	}
	ensureGeodata()

	if err := hub.Parse(nil); err != nil {
		return cError(fmt.Errorf("start core: %w", err))
	}

	started = true
	return nil
}

func resetTunListener() {
	// ReCreateTun serializes against config reloads and clears mihomo's cached
	// configuration without modifying the mihomo subproject.
	listener.ReCreateTun(LC.Tun{}, tunnel.Tunnel)
}

// prepare downloads the GeoIP/GeoSite databases the configuration references
// and leaves the rest of the start to start()/startTun().
//
// Android calls it before the VpnService establishes its TUN: once that
// interface owns 0.0.0.0/0 every socket this process opens is routed into a
// tunnel no one is reading yet, so a download started afterwards only stalls
// until it fails. Preparing first keeps the download on the phone's normal
// network.
//
//export prepare
func prepare(configDir *C.char) *C.char {
	mu.Lock()
	defer mu.Unlock()

	enableEmbeddedConfigUpdates()

	if err := setHomeDir(C.GoString(configDir)); err != nil {
		return cError(err)
	}
	ensureGeodata()

	return nil
}

// startTun starts the core like start() but forces tun.enable to true, using
// the remaining TUN options declared in configDir/config.yaml.
//
// fd is the descriptor of the tun device that an Android VpnService already
// established. The core takes ownership of it and closes it on stop(), so hand
// over detachFd() instead of keeping a ParcelFileDescriptor open as well. Pass 0
// (or a negative value) when the core may create the device itself, in which
// case the file-descriptor from the config file is kept.
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

	if err := setHomeDir(C.GoString(configDir)); err != nil {
		return cError(err)
	}
	if fd <= 0 {
		// Without a VpnService interface the phone's own network is still
		// reachable, so the databases can be fetched here as well. With a
		// descriptor the caller is expected to have called prepare() first:
		// downloading now would only feed the tunnel.
		ensureGeodata()
	}

	cfg, err := executor.Parse()
	if err != nil {
		return cError(fmt.Errorf("parse config: %w", err))
	}

	if fd > 0 && (cfg.Controller == nil || cfg.Controller.ExternalControllerUnix == "") {
		return cError(errors.New("external-controller-unix is not configured in config.yaml; configDir may not have been loaded"))
	}

	// Recreate the whole runtime on every startTun call.
	if tunListener != nil {
		_ = tunListener.Close()
		tunListener = nil
	}
	if started {
		executor.Shutdown()
		started = false
	}

	// Let mihomo apply the complete config except TUN. TUN is created below
	// directly through sing_tun.New, exactly like FlClash does, so mixed/system
	// stacks can bind to the VpnService address and are not limited by hub's
	// route/listener bookkeeping.
	cfg.General.Tun.Enable = false
	hub.ApplyConfig(cfg)

	if fd <= 0 {
		started = true
		return nil
	}

	options := buildFdTunOptions(cfg, int(fd), runtime.GOOS)
	listener, err := sing_tun.New(options, tunnel.Tunnel)
	if err != nil {
		executor.Shutdown()
		return cError(fmt.Errorf("start tun: %w", err))
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

	options := LC.Tun{
		Enable:              true,
		Device:              device,
		Stack:               stack,
		DNSHijack:           dnsHijack,
		AutoRoute:           false,
		AutoDetectInterface: false,
		Inet4Address: []netip.Prefix{
			netip.MustParsePrefix("172.19.0.1/30"),
		},
		Inet6Address: []netip.Prefix{
			netip.MustParsePrefix("fdfe:dcba:9876::1/126"),
		},
		MTU:            mtu,
		FileDescriptor: fd,
	}

	// recvmsgx/sendmsgx are utun-only extensions. Applying them to the
	// socketpair an iOS Packet Tunnel supplies makes sing-tun issue
	// UTUN_OPT_MAX_PENDING_PACKETS on a non-utun descriptor, which fails and
	// aborts the whole start. Ignore the profile's value on iOS.
	if goos != "ios" {
		options.RecvMsgX = cfg.General.Tun.RecvMsgX
		options.SendMsgX = cfg.General.Tun.SendMsgX
	}

	return options
}

// applyTunOptions forces TUN on. A positive fd makes sing-tun adopt that
// descriptor, which is how a VpnService supplied interface is used: sing-tun
// then leaves addresses, routes and rules to the system that created it.
func applyTunOptions(cfg *config.Config, fd int) {
	cfg.General.Tun.Enable = true

	// Android VpnService owns routing and interface selection. Disabling these
	// avoids sing-tun's Android netlink monitor, which is unavailable to normal
	// Android apps and otherwise makes TUN creation fail.
	cfg.General.Tun.AutoRoute = false
	cfg.General.Tun.AutoDetectInterface = false
	cfg.General.Tun.MTU = 1500
	cfg.General.Tun.Inet4Address = []netip.Prefix{
		netip.MustParsePrefix("172.19.0.1/30"),
	}
	cfg.General.Tun.Inet6Address = []netip.Prefix{
		netip.MustParsePrefix("fdfe:dcba:9876::1/126"),
	}
	cfg.General.Tun.DNSHijack = []string{"0.0.0.0:53"}

	if fd > 0 {
		cfg.General.Tun.FileDescriptor = fd
	}
}

// refreshProfile downloads url, applies the profile script and overlays the
// app-owned keys of the config currently in configDir, writing the result back
// to configDir/config.yaml.
//
// The mobile runtimes call this instead of reimplementing the refresh: the
// download, the JavaScript transform and the key overlay all live in
// internal/profilerefresh, the same code the desktop daemon runs. The previous
// file is kept as config.yaml.bak so the caller can roll back when the core
// rejects the new one.
//
// The core is not restarted: callers decide whether to restart based on
// whether the tunnel is already running this profile.
//
//export refreshProfile
func refreshProfile(configDir *C.char, url *C.char, script *C.char) *C.char {
	mu.Lock()
	defer mu.Unlock()

	dir := C.GoString(configDir)
	if dir == "" {
		return cError(errors.New("config dir is empty"))
	}
	subscription := C.GoString(url)
	if subscription == "" {
		return cError(errors.New("profile url is empty"))
	}
	transform := ""
	if script != nil {
		transform = C.GoString(script)
	}

	if err := profilerefresh.RefreshFile(dir, subscription, transform); err != nil {
		return cError(err)
	}
	return nil
}

// stop shuts the core down and closes every listener, including TUN.
//
//export stop
func stop() *C.char {
	mu.Lock()
	defer mu.Unlock()

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

	resetTunListener()
	tunnel.OnSuspend()
	started = false
	return nil
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

// ensureGeodata fetches the GeoIP/GeoSite databases the current configuration
// references. mihomo downloads them lazily while parsing rules and aborts the
// parse when a download fails, so a flaky CDN would otherwise take the whole
// start down. Callers must have pointed mihomo at its home directory first.
func ensureGeodata() {
	geoensure.Ensure(filepath.Join(constant.Path.HomeDir(), configFileName))
}

// cError converts a Go error into a heap allocated C string.
func cError(err error) *C.char {
	if err == nil {
		return nil
	}
	return C.CString(err.Error())
}
