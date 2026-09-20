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
	"sync"
	"unsafe"

	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/hub/route"
	"github.com/metacubex/mihomo/listener"
)

// configFileName is the file mihomo reads from the -d home directory.
const configFileName = "config.yaml"

var (
	mu      sync.Mutex
	started bool
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

	if err := setHomeDir(C.GoString(configDir)); err != nil {
		return cError(err)
	}

	if err := hub.Parse(nil); err != nil {
		return cError(fmt.Errorf("start core: %w", err))
	}

	started = true
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

	cfg, err := executor.Parse()
	if err != nil {
		return cError(fmt.Errorf("parse config: %w", err))
	}

	if fd > 0 && (cfg.Controller == nil || cfg.Controller.ExternalControllerUnix == "") {
		return cError(errors.New("external-controller-unix is not configured in config.yaml; configDir may not have been loaded"))
	}

	applyTunOptions(cfg, int(fd))

	hub.ApplyConfig(cfg)
	started = true
	return nil
}

// applyTunOptions forces TUN on. A positive fd makes sing-tun adopt that
// descriptor, which is how a VpnService supplied interface is used: sing-tun
// then leaves addresses, routes and rules to the system that created it.
func applyTunOptions(cfg *config.Config, fd int) {
	cfg.General.Tun.Enable = true
	cfg.General.Tun.Stack = constant.TunGvisor

	// Keep mihomo's TUN model in sync with the Android VpnService builder.
	// Do not disable AutoRoute/AutoDetectInterface here: that previously broke
	// startup on Android. Only sync the values that affect DNS/data plane.
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

// stop shuts the core down and closes every listener, including TUN.
//
//export stop
func stop() *C.char {
	mu.Lock()
	defer mu.Unlock()

	if started {
		executor.Shutdown()
	}

	// Also close any TUN listener that may have been created by a partially
	// failed start but was not tracked by executor.Shutdown.
	listener.Cleanup()
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

// cError converts a Go error into a heap allocated C string.
func cError(err error) *C.char {
	if err == nil {
		return nil
	}
	return C.CString(err.Error())
}
