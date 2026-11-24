//go:build darwin || linux || windows

// Command clashService is the desktop daemon behind Clashy.
//
// It replaces the retired Dart daemon (formerly `packages/cmd/bin/clashyService.dart`
// plus `package:server`) and keeps the same IPC endpoint and HTTP API, so the
// Flutter application needs no changes:
//
//	GET  /                 fixed greeting
//	GET  /version          service version the app compares before reinstalling
//	GET  /baseInfo/path    resolved executable path
//	GET  /baseInfo/env     process environment
//	GET  /clash            {"dir":...,"work":...}
//	GET  /clash/status     whether the core is running
//	GET  /clash/vpn/status whether the TUN listener is up
//	POST /clash            start the core with TUN enabled
//	POST /clash/core       start the core without TUN
//	POST /clash/vpn/start  enable TUN for the current configuration
//	POST /clash/vpn/stop   disable TUN and keep the core running
//	POST /clash/reload     restart the core with the configuration on disk
//	POST /clash/profile    switch the subscription a running service refreshes
//	POST /clash/stop       stop the core and forget the persisted state
//
// The IPC endpoint is `/tmp/clashy/clash_service.sock` on POSIX systems and the
// named pipe `\\.\pipe\clashy\clash_service.pipe` on Windows.
//
// Unlike the Dart server, which drove a `libclash` shared library through FFI,
// this daemon embeds mihomo in-process and owns the whole desktop lifecycle:
// privileged TUN provisioning through `mihomo-so/tunbroker` (LaunchDaemon on
// macOS, systemd unit on Linux, Windows service on Windows), subscription
// refresh, state persistence and the post-wake TUN health check.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/netip"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"sync"
	"time"

	"mihomo-so/tunbroker"

	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
	mihomoListener "github.com/metacubex/mihomo/listener"
	LC "github.com/metacubex/mihomo/listener/config"
	"github.com/metacubex/mihomo/listener/sing_tun"
	"github.com/metacubex/mihomo/tunnel"
	"go.yaml.in/yaml/v3"
)

const (
	// serviceVersion must stay below the app's own version so
	// `ClashService.updateDesktopServiceIfOutdated` reinstalls stale daemons.
	serviceVersion = "0.0.1"

	serviceSocketUnixPath = "/tmp/clashy/clash_service.sock"
	servicePipePath       = `\\.\pipe\clashy\clash_service.pipe`

	configFileName = "config.yaml"
	stateFileName  = "clash-state.json"

	// wakeSettleDelay gives the network time to come back after a system wake
	// before the TUN listener is recreated.
	wakeSettleDelay = 5 * time.Second
	// tunHealthInterval mirrors the desktop health poll of the Dart server. The
	// macOS IOKit wake notification is replaced by the same periodic check.
	tunHealthInterval = 30 * time.Second
	// minUpdateDelay keeps a fresh start from immediately downloading again.
	minUpdateDelay = 10 * time.Minute
	// requestTimeout bounds a subscription download.
	requestTimeout = 15 * time.Second
	// serviceUserAgent is the User-Agent providers expect from Clash clients.
	serviceUserAgent = "clash/mihomo"
	// apiErrorCode is the envelope code every failure uses, matching the app.
	apiErrorCode = 1001
	// maxRequestBody and maxSubscriptionSize guard against runaway payloads.
	maxRequestBody      = 8 << 20
	maxSubscriptionSize = 32 << 20
)

// configOverrideKeys are the top-level keys owned by the app.
//
// The app writes device-specific settings (ports, TUN, DNS, controller
// socket ...) and GeoX CDN URLs into `config.yaml`; subscription updates must
// keep those values instead of whatever the provider ships.
var configOverrideKeys = []string{
	"external-controller-unix",
	"external-controller-pipe",
	"log-level",
	"mixed-port",
	"mode",
	"ipv6",
	"allow-lan",
	"tun",
	"dns",
	"geox-url",
}

func main() {
	runPlatformService()
}

// serviceSocketPath returns the IPC endpoint of the control API.
func serviceSocketPath() string {
	if runtime.GOOS == "windows" {
		return servicePipePath
	}
	return serviceSocketUnixPath
}

// argumentValue returns the value of "--name value" or "--name=value" in the
// process arguments. The macOS LaunchAgent passes the app path and socket
// arguments this way.
func argumentValue(name string) string {
	args := os.Args[1:]
	for index := 0; index+1 < len(args); index++ {
		if args[index] == name {
			return args[index+1]
		}
	}
	for _, arg := range args {
		if strings.HasPrefix(arg, name+"=") {
			return strings.TrimPrefix(arg, name+"=")
		}
	}
	return ""
}

// ---------------------------------------------------------------- HTTP layer

// apiResponse is the response envelope the Flutter app decodes.
type apiResponse struct {
	Code int    `json:"code"`
	Msg  string `json:"msg"`
	Data any    `json:"data"`
}

func okResp(data any) *apiResponse {
	return &apiResponse{Code: 0, Msg: "", Data: data}
}

func errResp(data any) *apiResponse {
	return &apiResponse{Code: apiErrorCode, Msg: "", Data: data}
}

func errMsgResp(msg string) *apiResponse {
	return errResp(msg)
}

// serve runs the control API until ctx is cancelled. ready, when not nil, is
// closed once the IPC endpoint is accepting connections.
func serve(ctx context.Context, ready chan<- struct{}) error {
	core.initialize()

	listener, err := listenServiceEndpoint(serviceSocketPath())
	if err != nil {
		return err
	}
	defer listener.Close()

	server := &http.Server{Handler: http.HandlerFunc(handleHTTP)}
	serveErr := make(chan error, 1)
	go func() { serveErr <- server.Serve(listener) }()

	logf("serving %s (%s)", serviceSocketPath(), serviceVersion)
	go core.watchTunHealth(ctx)

	if ready != nil {
		close(ready)
	}

	select {
	case <-ctx.Done():
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		if err := server.Shutdown(shutdownCtx); err != nil {
			// A stuck client connection must not keep the daemon (and the SCM
			// stop request) waiting forever.
			_ = server.Close()
		}
		_ = core.shutdown()
		<-serveErr
		return nil
	case err := <-serveErr:
		if errors.Is(err, http.ErrServerClosed) {
			return nil
		}
		return err
	}
}

func handleHTTP(w http.ResponseWriter, r *http.Request) {
	started := time.Now()
	res, status := safeRoute(w, r)

	if res == nil {
		http.Error(w, http.StatusText(status), status)
	} else {
		payload, err := json.Marshal(res)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			logf("%s %s -> %d (%dms)", r.Method, r.URL.Path, http.StatusInternalServerError, time.Since(started).Milliseconds())
			return
		}
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(status)
		_, _ = w.Write(payload)
	}
	logf("%s %s -> %d (%dms)", r.Method, r.URL.Path, status, time.Since(started).Milliseconds())
}

// safeRoute turns a handler panic into the same error envelope the Dart server
// returned, instead of dropping the connection.
func safeRoute(w http.ResponseWriter, r *http.Request) (res *apiResponse, status int) {
	defer func() {
		if recovered := recover(); recovered != nil {
			logf("panic while handling %s %s: %v", r.Method, r.URL.Path, recovered)
			res, status = errResp(fmt.Sprint(recovered)), http.StatusOK
		}
	}()
	return route(w, r)
}

// route dispatches one request. It returns a nil response for statuses that
// are not wrapped in the API envelope (404, 405).
func route(_ http.ResponseWriter, r *http.Request) (*apiResponse, int) {
	switch r.URL.Path {
	case "/":
		if r.Method != http.MethodGet {
			return nil, http.StatusMethodNotAllowed
		}
		return okResp("Clash VPN!"), http.StatusOK

	case "/version":
		if r.Method != http.MethodGet {
			return nil, http.StatusMethodNotAllowed
		}
		return okResp(serviceVersion), http.StatusOK

	case "/baseInfo/path":
		if r.Method != http.MethodGet {
			return nil, http.StatusMethodNotAllowed
		}
		executable, err := os.Executable()
		if err != nil {
			return errMsgResp(err.Error()), http.StatusOK
		}
		return okResp(executable), http.StatusOK

	case "/baseInfo/env":
		if r.Method != http.MethodGet {
			return nil, http.StatusMethodNotAllowed
		}
		env := make(map[string]string)
		for _, entry := range os.Environ() {
			if key, value, found := strings.Cut(entry, "="); found {
				env[key] = value
			}
		}
		return okResp(env), http.StatusOK

	case "/clash":
		if r.Method == http.MethodGet {
			return okResp(clashRuntimeInfo()), http.StatusOK
		}
		if r.Method != http.MethodPost {
			return nil, http.StatusMethodNotAllowed
		}
		data, res := readBody(r)
		if res != nil {
			return res, http.StatusOK
		}
		return startProfile(data, true), http.StatusOK

	case "/clash/status":
		if r.Method != http.MethodGet {
			return nil, http.StatusMethodNotAllowed
		}
		started, _ := core.status()
		return okResp(started), http.StatusOK

	case "/clash/vpn/status":
		if r.Method != http.MethodGet {
			return nil, http.StatusMethodNotAllowed
		}
		_, vpn := core.status()
		return okResp(vpn), http.StatusOK

	case "/clash/core", "/clash/vpn/start":
		if r.Method != http.MethodPost {
			return nil, http.StatusMethodNotAllowed
		}
		data, res := readBody(r)
		if res != nil {
			return res, http.StatusOK
		}
		// `/clash` and `/clash/vpn/start` both ask for TUN; `/clash/core`
		// only boots the proxy so the app can load proxies first.
		return startProfile(data, r.URL.Path == "/clash/vpn/start"), http.StatusOK

	case "/clash/vpn/stop":
		if r.Method != http.MethodPost {
			return nil, http.StatusMethodNotAllowed
		}
		return stopVpn(), http.StatusOK

	case "/clash/reload":
		if r.Method != http.MethodPost {
			return nil, http.StatusMethodNotAllowed
		}
		return reloadConfig(), http.StatusOK

	case "/clash/profile":
		if r.Method != http.MethodPost {
			return nil, http.StatusMethodNotAllowed
		}
		data, res := readBody(r)
		if res != nil {
			return res, http.StatusOK
		}
		return updateProfile(data), http.StatusOK

	case "/clash/stop":
		if r.Method != http.MethodPost {
			return nil, http.StatusMethodNotAllowed
		}
		return stopClash(), http.StatusOK
	}

	return nil, http.StatusNotFound
}

func clashRuntimeInfo() map[string]string {
	dir := ""
	if executable, err := os.Executable(); err == nil {
		dir = executable
	}
	work := ""
	if cwd, err := os.Getwd(); err == nil {
		work = cwd
	}
	return map[string]string{"dir": dir, "work": work}
}

// readBody applies the JSON middleware of the Dart server: only
// `application/json` bodies are accepted, and a body that is not valid JSON is
// treated as a plain string, which keeps older clients posting the raw
// configuration directory working.
func readBody(r *http.Request) (any, *apiResponse) {
	if contentType := r.Header.Get("Content-Type"); contentType != "" &&
		!strings.HasPrefix(contentType, "application/json") {
		return nil, errMsgResp("content-type != application/json")
	}

	payload, err := io.ReadAll(io.LimitReader(r.Body, maxRequestBody))
	if err != nil {
		return nil, errMsgResp(err.Error())
	}
	if len(payload) == 0 {
		return "", nil
	}

	var data any
	if err := json.Unmarshal(payload, &data); err != nil {
		return string(payload), nil
	}
	return data, nil
}

// ------------------------------------------------------------- API handlers

func startProfile(data any, vpnEnabled bool) *apiResponse {
	profile := parseProfile(data)
	if profile == nil || profile.ConfigDir == "" {
		return errMsgResp("invalid profile")
	}

	if err := core.run(profile.ConfigDir, vpnEnabled); err != nil {
		return errResp(err.Error())
	}
	core.setProfile(profile)
	if err := core.commitAPIState(profile, vpnEnabled); err != nil {
		return errMsgResp("save Clash state failed: " + err.Error())
	}
	return okResp(nil)
}

func updateProfile(data any) *apiResponse {
	profile := parseProfile(data)
	if profile == nil {
		return errMsgResp("invalid profile")
	}

	configDir := core.apiConfigDir()
	if configDir == "" {
		configDir = core.runtimeConfigDir()
	}
	if profile.ConfigDir == "" && configDir == "" {
		return errMsgResp("invalid profile")
	}

	apiProfile := profile
	if profile.ConfigDir == "" {
		apiProfile = profile.withConfigDir(configDir)
	}

	core.updateProfile(apiProfile)
	if err := core.commitAPIState(apiProfile, core.desiredVpnEnabled()); err != nil {
		return errMsgResp("save Clash state failed: " + err.Error())
	}
	return okResp(nil)
}

func stopVpn() *apiResponse {
	if err := core.stopVpn(); err != nil {
		return errResp(err.Error())
	}

	configDir := core.apiConfigDir()
	if configDir == "" {
		configDir = core.runtimeConfigDir()
	}
	if configDir != "" {
		if err := core.commitAPIState(core.apiProfileSnapshot(), false); err != nil {
			return errMsgResp("save Clash state failed: " + err.Error())
		}
	}
	return okResp(nil)
}

func reloadConfig() *apiResponse {
	if err := core.reload(); err != nil {
		return errResp(err.Error())
	}
	return okResp(nil)
}

func stopClash() *apiResponse {
	if err := core.stop(); err != nil {
		return errResp(err.Error())
	}
	if err := core.clearAPIState(); err != nil {
		return errMsgResp("clear Clash state failed: " + err.Error())
	}
	return okResp(nil)
}

// ------------------------------------------------------ profile and scheduling

// clashProfile is the JSON shape the app sends and the state file stores.
type clashProfile struct {
	ConfigDir string `json:"configDir"`
	ID        string `json:"id,omitempty"`
	Name      string `json:"name,omitempty"`
	URL       string `json:"url,omitempty"`
	// Script is accepted for compatibility. The Dart server evaluated it with
	// a JavaScript interpreter; this daemon has no JS engine, so it is ignored
	// with a log line instead of silently producing a different config.
	Script string `json:"script,omitempty"`
	// UpdateInterval is the subscription refresh interval in minutes. Zero or
	// negative disables the automatic updates, matching the Dart model.
	UpdateInterval int `json:"updateInterval,omitempty"`
	// UpdateTime is when the subscription was last downloaded, in the local
	// ISO-8601 form Dart writes ("2006-01-02T15:04:05.000").
	UpdateTime string `json:"updateTime,omitempty"`
}

func (p *clashProfile) withConfigDir(configDir string) *clashProfile {
	copied := *p
	copied.ConfigDir = configDir
	return &copied
}

func (p *clashProfile) withUpdateTime(updateTime time.Time) *clashProfile {
	copied := *p
	copied.UpdateTime = dartLocalTime(updateTime)
	return &copied
}

func (p *clashProfile) displayName() string {
	switch {
	case p.Name != "":
		return p.Name
	case p.ID != "":
		return p.ID
	default:
		return p.URL
	}
}

// nextUpdateDelay mirrors `ClashProfile.nextUpdateDelay`: a profile that is
// already due still waits minUpdateDelay so a fresh start is not immediately
// followed by another download.
func (p *clashProfile) nextUpdateDelay(now time.Time) (time.Duration, bool) {
	last, ok := parseProfileTime(p.UpdateTime)
	if !ok || p.UpdateInterval <= 0 {
		return 0, false
	}

	due := last.Add(time.Duration(p.UpdateInterval) * time.Minute)
	if !due.After(now) {
		return minUpdateDelay, true
	}
	delay := due.Sub(now)
	if delay < minUpdateDelay {
		return minUpdateDelay, true
	}
	return delay, true
}

func parseProfileTime(value string) (time.Time, bool) {
	if value == "" {
		return time.Time{}, false
	}
	// Dart writes local timestamps without an offset, so they must be parsed
	// against time.Local; time.Parse would otherwise read them as UTC.
	if parsed, err := time.ParseInLocation("2006-01-02T15:04:05.999999999", value, time.Local); err == nil {
		return parsed, true
	}
	if parsed, err := time.Parse(time.RFC3339Nano, value); err == nil {
		return parsed, true
	}
	return time.Time{}, false
}

// dartLocalTime formats a timestamp the way Dart's `toIso8601String` does for a
// local DateTime, which is what the app writes into the state file.
func dartLocalTime(t time.Time) string {
	return t.Format("2006-01-02T15:04:05.000")
}

func parseProfile(data any) *clashProfile {
	switch value := data.(type) {
	case string:
		if value == "" {
			return nil
		}
		// Older clients post the configuration directory as a plain string.
		return &clashProfile{ConfigDir: value}
	case map[string]any:
		payload, err := json.Marshal(value)
		if err != nil {
			return nil
		}
		var profile clashProfile
		if err := json.Unmarshal(payload, &profile); err != nil {
			return nil
		}
		return &profile
	default:
		return nil
	}
}

// ------------------------------------------------------------- core runtime

var core = newCoreRuntime()

type coreRuntime struct {
	mu sync.Mutex

	statePath string

	// Observed runtime state, changed only by native start/stop operations.
	started      bool
	runtimeVPN   bool
	configDir    string
	profile      *clashProfile
	profileTimer *time.Timer
	tunInterface string

	// Desired state, hydrated from disk and changed only by API commits.
	apiProfile *clashProfile
	desiredVPN bool

	recovering bool
}

func newCoreRuntime() *coreRuntime {
	runtime := &coreRuntime{}
	path, err := stateFilePath()
	if err != nil {
		logf("persisted Clash state is unavailable: %v", err)
	} else {
		runtime.statePath = path
	}
	return runtime
}

func stateFilePath() (string, error) {
	if runtime.GOOS == "darwin" {
		home := os.Getenv("HOME")
		if home == "" {
			return "", errors.New("HOME is not set for the macOS service process")
		}
		return filepath.Join(home, "Library", "Application Support", "Clashy", stateFileName), nil
	}
	if appData := os.Getenv("APPDATA"); appData != "" {
		return filepath.Join(appData, "Clashy", stateFileName), nil
	}
	if configHome := os.Getenv("XDG_CONFIG_HOME"); configHome != "" {
		return filepath.Join(configHome, "clashy", stateFileName), nil
	}
	if home := os.Getenv("HOME"); home != "" {
		return filepath.Join(home, ".config", "clashy", stateFileName), nil
	}
	// systemd system services usually have no HOME.
	return filepath.Join("/var/lib/clashy", stateFileName), nil
}

// initialize restores the desired state persisted before the last shutdown.
func (c *coreRuntime) initialize() {
	c.restorePersisted()
}

func (c *coreRuntime) status() (started bool, vpnEnabled bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.started, c.runtimeVPN
}

func (c *coreRuntime) runtimeConfigDir() string {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.configDir
}

func (c *coreRuntime) desiredVpnEnabled() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.desiredVPN
}

func (c *coreRuntime) apiConfigDir() string {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.apiProfile == nil {
		return ""
	}
	return c.apiProfile.ConfigDir
}

func (c *coreRuntime) apiProfileSnapshot() *clashProfile {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.apiProfile
}

func (c *coreRuntime) run(configDir string, vpnEnabled bool) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.runLocked(configDir, vpnEnabled)
}

func (c *coreRuntime) setProfile(profile *clashProfile) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.replaceProfileLocked(profile)
}

func (c *coreRuntime) updateProfile(profile *clashProfile) {
	c.mu.Lock()
	defer c.mu.Unlock()

	currentConfigDir := c.configDir
	if c.profile != nil && c.profile.ConfigDir != "" {
		currentConfigDir = c.profile.ConfigDir
	}
	if profile.ConfigDir == "" && currentConfigDir != "" {
		profile = profile.withConfigDir(currentConfigDir)
	}
	c.replaceProfileLocked(profile)
}

func (c *coreRuntime) stopVpn() error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if !c.started || c.configDir == "" {
		return nil
	}
	return c.runLocked(c.configDir, false)
}

func (c *coreRuntime) reload() error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if !c.started || c.configDir == "" {
		return errors.New("Clash core is not running")
	}

	configDir := c.configDir
	vpnEnabled := c.desiredVPN
	if err := c.stopLocked(); err != nil {
		return err
	}
	return c.runLocked(configDir, vpnEnabled)
}

// stop stops the runtime without touching the persisted desired state. The
// stop endpoint separately clears it after a successful stop.
func (c *coreRuntime) stop() error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if err := c.stopLocked(); err != nil {
		return err
	}
	if c.profileTimer != nil {
		c.profileTimer.Stop()
		c.profileTimer = nil
	}
	c.profile = nil
	return nil
}

// shutdown stops the core when the daemon exits, keeping the state file for the
// next start.
func (c *coreRuntime) shutdown() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.profileTimer != nil {
		c.profileTimer.Stop()
		c.profileTimer = nil
	}
	return c.stopLocked()
}

func (c *coreRuntime) replaceProfileLocked(profile *clashProfile) {
	c.profile = profile
	c.scheduleProfileUpdateLocked()
}

func (c *coreRuntime) scheduleProfileUpdateLocked() {
	if c.profileTimer != nil {
		c.profileTimer.Stop()
		c.profileTimer = nil
	}
	if c.profile == nil {
		return
	}

	delay, ok := c.profile.nextUpdateDelay(time.Now())
	if !ok {
		return
	}
	target := c.profile
	c.profileTimer = time.AfterFunc(delay, func() { c.updateFromSubscription(target) })
}

// runLocked starts (or restarts) the core for configDir. The caller holds mu.
func (c *coreRuntime) runLocked(configDir string, vpnEnabled bool) error {
	if c.configDir == configDir && c.started && c.runtimeVPN == vpnEnabled {
		return nil
	}

	// Every desktop platform goes through the privileged helper: it owns the
	// TUN device, its descriptor (POSIX) or the Wintun adapter (Windows).
	if vpnEnabled {
		if err := ensureTunHelper(); err != nil {
			logf("register TUN helper failed: %v", err)
			return fmt.Errorf("register TUN helper failed: %w", err)
		}
	}

	var interfacesBefore []string
	if runtime.GOOS == "darwin" {
		interfacesBefore, _ = listTunInterfaces()
	}

	c.started = false
	c.runtimeVPN = false
	err := startEngine(configDir, vpnEnabled)

	c.configDir = configDir
	c.started = err == nil && engineStarted()
	c.runtimeVPN = err == nil && engineStarted() && vpnEnabled
	if err != nil {
		c.tunInterface = ""
		return err
	}

	switch {
	case !vpnEnabled:
		c.tunInterface = ""
	case runtime.GOOS == "darwin":
		// macOS assigns the utun device name in the kernel, so identify it by
		// diffing the interface list around the start.
		interfacesAfter, listErr := listTunInterfaces()
		if listErr == nil {
			c.tunInterface = firstDifference(interfacesAfter, interfacesBefore)
		}
		if c.tunInterface == "" {
			logf("unable to identify Clash TUN interface after start")
		}
	default:
		// The Linux and Windows helpers document a fixed interface name.
		c.tunInterface = tunbroker.InterfaceName
	}
	return nil
}

func (c *coreRuntime) stopLocked() error {
	err := stopEngine()
	c.started = engineStarted()
	if !c.started {
		c.configDir = ""
		c.runtimeVPN = false
	}
	return err
}

// restartLocked forces a full stop/start cycle. The caller holds mu.
func (c *coreRuntime) restartLocked(configDir string, vpnEnabled bool) error {
	if err := c.stopLocked(); err != nil {
		return err
	}
	return c.runLocked(configDir, vpnEnabled)
}

func firstDifference(values []string, previous []string) string {
	for _, value := range values {
		seen := false
		for _, candidate := range previous {
			if candidate == value {
				seen = true
				break
			}
		}
		if !seen {
			return value
		}
	}
	return ""
}

// --------------------------------------------------------- core engine

// engineState keeps the mihomo listeners owned by this process. Every field is
// guarded by coreRuntime.mu: only start/stop paths touch it.
var engine struct {
	started      bool
	tun          *sing_tun.Listener
	brokerActive bool
}

func engineStarted() bool { return engine.started }

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

// startEngine applies configDir/config.yaml. With vpnEnabled it also brings up
// the TUN interface; without it only the proxy listeners and the controller run.
func startEngine(configDir string, vpnEnabled bool) error {
	if err := setHomeDir(configDir); err != nil {
		return err
	}

	cfg, err := executor.Parse()
	if err != nil {
		return fmt.Errorf("parse config: %w", err)
	}

	if err := resetTunListener(); err != nil {
		if engine.started {
			executor.Shutdown()
			engine.started = false
		}
		return err
	}
	if engine.started {
		executor.Shutdown()
		engine.started = false
	}

	// Every desktop platform asks the privileged helper for the TUN device. The
	// TUN listener itself is created below through sing_tun.New: the helper owns
	// the device and the core only attaches to it, while routes are installed by
	// the helper on POSIX and by mihomo on Windows (Wintun has no descriptor to
	// pass, only the adapter name).

	tunFD, tunInterface := 0, ""
	if vpnEnabled {
		tunFD, tunInterface, err = requestTunLease(cfg)
		if err != nil {
			return err
		}
		engine.brokerActive = true
	}

	cfg.General.Tun.Enable = false
	hub.ApplyConfig(cfg)

	if !vpnEnabled {
		engine.started = true
		return nil
	}

	// POSIX helpers hand back a real descriptor; the Windows helper provisions
	// the Wintun adapter and returns fd=0 plus the adapter name instead.
	tunFDUsable := tunFD > 0
	tunDeviceUsable := runtime.GOOS == "windows" && tunInterface != ""
	if !tunFDUsable && !tunDeviceUsable {
		if engine.brokerActive {
			engine.brokerActive = false
			_ = tunbroker.Deactivate()
		}
		return errors.New("TUN helper returned no usable TUN device")
	}

	tunListener, err := sing_tun.New(desktopTunOptions(cfg, tunFD, tunInterface), tunnel.Tunnel)
	if err != nil {
		_ = closeDesktopTunFD(tunFD)
		if engine.brokerActive {
			_ = tunbroker.Deactivate()
			engine.brokerActive = false
		}
		executor.Shutdown()
		return fmt.Errorf("start tun: %w", err)
	}

	if engine.brokerActive {
		if err := tunbroker.Activate(); err != nil {
			_ = tunListener.Close()
			_ = tunbroker.Deactivate()
			engine.brokerActive = false
			executor.Shutdown()
			return fmt.Errorf("activate TUN helper routes: %w", err)
		}
	}

	engine.tun = tunListener
	engine.started = true
	return nil
}

func stopEngine() error {
	if err := resetTunListener(); err != nil {
		return err
	}
	tunnel.OnSuspend()
	engine.started = false
	return nil
}

func resetTunListener() error {
	var errs []error

	// Stop mihomo's readers before releasing the helper lease that owns the
	// underlying TUN device.
	if engine.tun != nil {
		if err := engine.tun.Close(); err != nil {
			errs = append(errs, err)
		}
		engine.tun = nil
	}
	if engine.brokerActive {
		if err := tunbroker.Deactivate(); err != nil {
			errs = append(errs, err)
		} else {
			engine.brokerActive = false
		}
	}
	// ReCreateTun clears mihomo's cached TUN configuration.
	mihomoListener.ReCreateTun(LC.Tun{}, tunnel.Tunnel)
	return errors.Join(errs...)
}

// requestTunLease asks the platform helper for the TUN device that the core
// attaches to. The macOS and Linux helpers create the device and return both its
// descriptor and name; the Windows helper provisions a Wintun adapter and returns
// fd=0 plus the adapter name, because there is no descriptor to hand over.
func requestTunLease(cfg *config.Config) (int, string, error) {
	tun := cfg.General.Tun
	if len(tun.RouteAddressSet) > 0 || len(tun.RouteExcludeAddressSet) > 0 {
		return -1, "", errors.New("TUN helper does not support route-address-set yet")
	}

	options := tunbroker.Config{
		MTU:       tun.MTU,
		AutoRoute: tun.AutoRoute,
	}
	for _, address := range tun.Inet4Address {
		options.Inet4Address = append(options.Inet4Address, address.String())
	}
	for _, address := range tun.Inet6Address {
		options.Inet6Address = append(options.Inet6Address, address.String())
	}
	if len(options.Inet4Address) == 0 {
		options.Inet4Address = []string{defaultInet4Address}
	}
	if len(options.Inet6Address) == 0 {
		options.Inet6Address = []string{defaultInet6Address}
	}
	for _, address := range tun.RouteAddress {
		options.RouteAddress = append(options.RouteAddress, address.String())
	}
	for _, address := range tun.Inet4RouteAddress {
		options.RouteAddress = append(options.RouteAddress, address.String())
	}
	for _, address := range tun.Inet6RouteAddress {
		options.RouteAddress = append(options.RouteAddress, address.String())
	}
	for _, address := range tun.RouteExcludeAddress {
		options.RouteExcludeAddress = append(options.RouteExcludeAddress, address.String())
	}
	for _, address := range tun.Inet4RouteExcludeAddress {
		options.RouteExcludeAddress = append(options.RouteExcludeAddress, address.String())
	}
	for _, address := range tun.Inet6RouteExcludeAddress {
		options.RouteExcludeAddress = append(options.RouteExcludeAddress, address.String())
	}

	fd, device, err := tunbroker.Acquire(options)
	if err != nil && runtime.GOOS == "windows" {
		// A helper that is installed but stopped (or one that could not be
		// registered because the caller is not an administrator) surfaces here
		// as a pipe error; say what actually has to be fixed.
		return fd, device, fmt.Errorf("%w (is the Clashy TUN helper service installed and running?)", err)
	}
	return fd, device, err
}

// desktopTunOptions builds the listener options for a helper supplied TUN.
func desktopTunOptions(cfg *config.Config, tunFD int, helperInterface string) LC.Tun {
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
		device = tunbroker.InterfaceName
	}

	inet4Address := cfg.General.Tun.Inet4Address
	if len(inet4Address) == 0 {
		inet4Address = []netip.Prefix{netip.MustParsePrefix(defaultInet4Address)}
	}
	inet6Address := cfg.General.Tun.Inet6Address
	if len(inet6Address) == 0 {
		inet6Address = []netip.Prefix{netip.MustParsePrefix(defaultInet6Address)}
	}

	return LC.Tun{
		Enable:                   true,
		Device:                   device,
		Stack:                    stack,
		DNSHijack:                []string{defaultDNSHijack},
		AutoRoute:                runtime.GOOS == "windows",
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
		FileDescriptor:           tunFD,
	}
}

const (
	defaultInet4Address = "172.19.0.1/30"
	defaultInet6Address = "fdfe:dcba:9876::1/126"
	defaultDNSHijack    = "172.19.0.2:53"
)

func closeDesktopTunFD(fd int) error {
	if runtime.GOOS == "windows" {
		return nil
	}
	if fd <= 2 {
		return fmt.Errorf("invalid TUN file descriptor: %d", fd)
	}
	return closeFileDescriptor(fd)
}

// ---------------------------------------------------------- state persistence

type persistedState struct {
	Profile    *clashProfile `json:"profile"`
	VPNEnabled *bool         `json:"vpnEnabled"`
}

func (c *coreRuntime) restorePersisted() {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.statePath == "" {
		return
	}
	payload, err := os.ReadFile(c.statePath)
	if err != nil {
		if !errors.Is(err, os.ErrNotExist) {
			logf("read saved Clash state failed: %v", err)
		}
		return
	}

	var state persistedState
	if err := json.Unmarshal(payload, &state); err != nil {
		logf("saved Clash state is invalid: %v", err)
		return
	}
	profile := state.Profile
	if profile == nil || profile.ConfigDir == "" {
		logf("saved Clash state has no configuration directory")
		return
	}

	vpnEnabled := true
	if state.VPNEnabled != nil {
		vpnEnabled = *state.VPNEnabled
	}

	c.apiProfile = profile
	c.desiredVPN = vpnEnabled
	logf("restoring Clash from saved state %s", c.statePath)

	if err := c.runLocked(profile.ConfigDir, vpnEnabled); err != nil {
		logf("restore Clash from saved state failed: %v", err)
		return
	}
	c.replaceProfileLocked(profile)
}

// commitAPIState writes the desired state submitted through the control API.
// Runtime recovery and background work must never call this method.
func (c *coreRuntime) commitAPIState(profile *clashProfile, vpnEnabled bool) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.statePath == "" {
		return errors.New("persisted state path is unavailable")
	}

	payload, err := json.Marshal(persistedState{Profile: profile, VPNEnabled: &vpnEnabled})
	if err != nil {
		return fmt.Errorf("encode Clash state: %w", err)
	}

	temporaryFile := c.statePath + ".tmp"
	if err := os.MkdirAll(filepath.Dir(c.statePath), 0o755); err != nil {
		return fmt.Errorf("create Clash state directory: %w", err)
	}
	if err := os.WriteFile(temporaryFile, payload, 0o644); err != nil {
		return fmt.Errorf("write Clash state: %w", err)
	}
	if err := os.Rename(temporaryFile, c.statePath); err != nil {
		return fmt.Errorf("commit Clash state: %w", err)
	}

	c.apiProfile = profile
	c.desiredVPN = vpnEnabled
	return nil
}

// clearAPIState forgets the desired state after an explicit stop request.
func (c *coreRuntime) clearAPIState() error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.statePath != "" {
		if err := os.Remove(c.statePath); err != nil && !errors.Is(err, os.ErrNotExist) {
			return fmt.Errorf("remove Clash state: %w", err)
		}
	}

	c.apiProfile = nil
	c.desiredVPN = false
	return nil
}

// ------------------------------------------------------------- subscription

func (c *coreRuntime) updateFromSubscription(target *clashProfile) {
	c.mu.Lock()
	if c.profile != target {
		c.scheduleProfileUpdateLocked()
		c.mu.Unlock()
		return
	}
	c.mu.Unlock()

	err := c.refreshConfig(target)

	c.mu.Lock()
	defer c.mu.Unlock()
	if c.profile != target {
		// Stopped or switched while the config was downloading.
		return
	}
	if err != nil {
		logf("profile update failed: %v", err)
		c.profile = target.withUpdateTime(time.Now())
		c.scheduleProfileUpdateLocked()
		return
	}
	c.profile = target.withUpdateTime(time.Now())
	c.scheduleProfileUpdateLocked()
	logf("profile updated: %s", target.displayName())
}

// refreshConfig downloads the subscription and restarts the core with the
// merged config. The previous config file is restored when the restart fails.
func (c *coreRuntime) refreshConfig(profile *clashProfile) error {
	if profile.URL == "" {
		return errors.New("profile url is empty")
	}

	configPath := filepath.Join(profile.ConfigDir, configFileName)
	current, err := os.ReadFile(configPath)
	if err != nil {
		return fmt.Errorf("missing config file: %s", configPath)
	}

	downloaded, err := downloadConfig(profile.URL)
	if err != nil {
		return err
	}

	merged, err := applyConfigOverrides(downloaded, string(current))
	if err != nil {
		return err
	}
	configured := merged
	if strings.TrimSpace(profile.Script) != "" {
		configured = runProfileScript(merged, profile.Script)
	}

	backupPath := configPath + ".bak"
	if err := os.WriteFile(backupPath, current, 0o644); err != nil {
		return fmt.Errorf("back up config: %w", err)
	}
	if err := os.WriteFile(configPath, []byte(configured), 0o644); err != nil {
		_ = os.Remove(backupPath)
		return fmt.Errorf("write config: %w", err)
	}

	// Restart only when the core is actually running that profile.
	c.mu.Lock()
	vpnEnabled := c.desiredVPN
	restart := c.started && c.profile == profile
	var restartErr error
	if restart {
		restartErr = c.restartLocked(profile.ConfigDir, vpnEnabled)
	}
	c.mu.Unlock()

	if !restart {
		_ = os.Remove(backupPath)
		return nil
	}
	if restartErr == nil {
		_ = os.Remove(backupPath)
		return nil
	}

	logf("restart with the updated config failed: %v", restartErr)
	restored, readErr := os.ReadFile(backupPath)
	if readErr == nil {
		if writeErr := os.WriteFile(configPath, restored, 0o644); writeErr != nil {
			logf("restore previous config failed: %v", writeErr)
		}
	}
	_ = os.Remove(backupPath)

	c.mu.Lock()
	var restoreErr error
	if c.profile == profile {
		restoreErr = c.restartLocked(profile.ConfigDir, vpnEnabled)
	}
	c.mu.Unlock()
	if restoreErr != nil {
		logf("restore previous config failed: %v", restoreErr)
	}
	return restartErr
}

func downloadConfig(url string) (string, error) {
	transport := &http.Transport{
		DialContext: (&net.Dialer{Timeout: requestTimeout}).DialContext,
	}
	client := &http.Client{Transport: transport}
	defer client.CloseIdleConnections()

	request, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		return "", fmt.Errorf("create subscription request: %w", err)
	}
	request.Header.Set("User-Agent", serviceUserAgent)

	response, err := client.Do(request)
	if err != nil {
		return "", fmt.Errorf("download subscription: %w", err)
	}
	defer response.Body.Close()

	if response.StatusCode >= http.StatusBadRequest {
		return "", fmt.Errorf("download subscription: unexpected status %s", response.Status)
	}

	payload, err := io.ReadAll(io.LimitReader(response.Body, maxSubscriptionSize))
	if err != nil {
		return "", fmt.Errorf("read subscription: %w", err)
	}
	return string(payload), nil
}

// runProfileScript is a compatibility stub. Profile scripts are JavaScript
// evaluated by the Dart service; this daemon has no JS engine, so the
// downloaded config is used unchanged and the gap is logged loudly instead of
// silently producing a different running configuration.
func runProfileScript(configText string, script string) string {
	logf("profile script is not supported by the Go service; ignoring it")
	return configText
}

// applyConfigOverrides keeps the app-owned top-level keys of current in
// downloaded, matching `applyConfigOverrides` of the Dart server.
func applyConfigOverrides(downloaded string, current string) (string, error) {
	var currentDoc yaml.Node
	if err := yaml.Unmarshal([]byte(current), &currentDoc); err != nil {
		return downloaded, nil
	}
	currentMapping := documentMapping(&currentDoc)
	if currentMapping == nil {
		return downloaded, nil
	}

	var downloadedDoc yaml.Node
	if err := yaml.Unmarshal([]byte(downloaded), &downloadedDoc); err != nil {
		return "", errors.New("downloaded config is not a YAML map")
	}
	downloadedMapping := documentMapping(&downloadedDoc)
	if downloadedMapping == nil {
		return "", errors.New("downloaded config is not a YAML map")
	}

	for _, key := range configOverrideKeys {
		value := mappingValue(currentMapping, key)
		if value == nil {
			continue
		}
		replaceMappingValue(downloadedMapping, key, value)
	}

	payload, err := yaml.Marshal(&downloadedDoc)
	if err != nil {
		return "", fmt.Errorf("write merged config: %w", err)
	}
	return string(payload), nil
}

func documentMapping(document *yaml.Node) *yaml.Node {
	if document.Kind == yaml.DocumentNode && len(document.Content) > 0 {
		mapping := document.Content[0]
		if mapping.Kind == yaml.MappingNode {
			return mapping
		}
	}
	return nil
}

func mappingValue(mapping *yaml.Node, key string) *yaml.Node {
	for index := 0; index+1 < len(mapping.Content); index += 2 {
		if mapping.Content[index].Value == key {
			return mapping.Content[index+1]
		}
	}
	return nil
}

func replaceMappingValue(mapping *yaml.Node, key string, value *yaml.Node) {
	for index := 0; index+1 < len(mapping.Content); index += 2 {
		if mapping.Content[index].Value == key {
			mapping.Content[index+1] = cloneNode(value)
			return
		}
	}
	keyNode := &yaml.Node{Kind: yaml.ScalarNode, Tag: "!!str", Value: key}
	mapping.Content = append(mapping.Content, keyNode, cloneNode(value))
}

func cloneNode(node *yaml.Node) *yaml.Node {
	if node == nil {
		return nil
	}
	copied := *node
	copied.Content = make([]*yaml.Node, len(node.Content))
	for index, child := range node.Content {
		copied.Content[index] = cloneNode(child)
	}
	return &copied
}

// ------------------------------------------------------------ TUN health

// watchTunHealth replaces the Dart macOS IOKit wake monitor with the periodic
// health poll the Dart server already used on Linux and Windows: after a system
// wake the TUN interface disappears, and the core has to be restarted.
func (c *coreRuntime) watchTunHealth(ctx context.Context) {
	ticker := time.NewTicker(tunHealthInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			c.recoverTun(false)
		}
	}
}

func (c *coreRuntime) recoverTun(logHealthy bool) {
	c.mu.Lock()
	if c.recovering || !c.started || !c.desiredVPN || !c.runtimeVPN || c.configDir == "" {
		c.mu.Unlock()
		return
	}
	configDir := c.configDir
	iface := c.tunInterface
	c.recovering = true
	hadInterface := iface != ""
	c.mu.Unlock()

	defer func() {
		c.mu.Lock()
		c.recovering = false
		c.mu.Unlock()
	}()

	if !configEnablesTun(configDir) {
		return
	}
	if !hadInterface {
		if logHealthy {
			logf("unable to verify TUN interface; skipping wake recovery")
		}
		return
	}
	if tunInterfaceHealthy(iface) {
		if logHealthy {
			logf("TUN is healthy after system wake; no restart needed")
		}
		return
	}

	if logHealthy {
		logf("system wake detected; TUN is unavailable, restoring it")
	} else {
		logf("TUN is unavailable; restoring it")
	}

	time.Sleep(wakeSettleDelay)

	c.mu.Lock()
	if !c.started || c.configDir != configDir {
		c.mu.Unlock()
		return
	}
	vpnEnabled := c.desiredVPN
	c.mu.Unlock()

	if err := c.restart(configDir, vpnEnabled); err != nil {
		logf("restore TUN after wake failed: %v", err)
		return
	}
	logf("TUN restored after system wake")
}

func (c *coreRuntime) restart(configDir string, vpnEnabled bool) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.restartLocked(configDir, vpnEnabled)
}

// configEnablesTun reports whether the configuration on disk declares a TUN
// section. A core-only configuration never needs wake recovery.
func configEnablesTun(configDir string) bool {
	payload, err := os.ReadFile(filepath.Join(configDir, configFileName))
	if err != nil {
		logf("read config for TUN health check failed: %v", err)
		return false
	}
	var shape struct {
		Tun struct {
			Enable bool `yaml:"enable"`
		} `yaml:"tun"`
	}
	if err := yaml.Unmarshal(payload, &shape); err != nil {
		logf("parse config for TUN health check failed: %v", err)
		return false
	}
	return shape.Tun.Enable
}

// ------------------------------------------------------------------ logging

func logf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "%s %s\n", time.Now().Format("15:04:05"), fmt.Sprintf(format, args...))
}
