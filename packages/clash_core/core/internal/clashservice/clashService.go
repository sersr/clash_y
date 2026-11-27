// Package clashsvc is the Clashy control API: one route table, one envelope,
// one profile implementation, and the desktop daemon that serves it.
//
// The desktop daemon (Run, per-OS in clashService_*.go) runs privileged and
// owns the whole lifecycle: the core, the TUN device, the persisted state, the
// subscription timer and the state file. A mobile tunnel process cannot do
// that — the OS owns the tunnel and the host code starts the core — so it
// implements only the profile half of the same Host interface and answers
// ErrUnsupported for the rest. Both serve the same route table from here.
package clashservice

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
	"runtime/debug"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	mihomoDNS "github.com/metacubex/mihomo/dns"
	"github.com/metacubex/mihomo/hub"
	"github.com/metacubex/mihomo/hub/executor"
	mihomoListener "github.com/metacubex/mihomo/listener"
	LC "github.com/metacubex/mihomo/listener/config"
	"github.com/metacubex/mihomo/listener/sing_tun"
	"github.com/metacubex/mihomo/tunnel"
	"go.yaml.in/yaml/v3"

	"mihomo-so/internal/geoensure"
	"mihomo-so/internal/profilerefresh"
	"mihomo-so/internal/profileschedule"
	"mihomo-so/internal/profilescheduler"
)

const (
	// serviceVersion must stay below the app's own version so
	// `ClashService.updateDesktopServiceIfOutdated` reinstalls stale daemons.
	serviceVersion = "0.0.1"

	serviceSocketUnixPath = "/tmp/clashy/clash_service.sock"
	servicePipePath       = `\\.\pipe\clashy\clash_service.pipe`

	configFileName = profilerefresh.ConfigFileName
	stateFileName  = "clash-state.json"

	// wakeSettleDelay gives the network time to come back after a system wake
	// before the TUN listener is recreated.
	wakeSettleDelay = 5 * time.Second
	// tunHealthInterval mirrors the desktop health poll of the Dart server. The
	// macOS IOKit wake notification is replaced by the same periodic check.
	tunHealthInterval = 30 * time.Second
	// minUpdateDelay keeps a fresh start from immediately downloading again.
	minUpdateDelay = 10 * time.Minute
)

// allowedClientUID restricts the control API to the desktop user that installed
// the service (root is always allowed). -1 means "not configured": the daemon
// then accepts any local user that can reach the endpoint.
var allowedClientUID int32 = -1

// allowedClientSID is the Windows counterpart of allowedClientUID: the SID of
// the installing user, used to build the service pipe DACL. Empty means
// "not configured".
var allowedClientSID string

// parseAccessRestrictions reads the client restrictions passed by the installer.
func parseAccessRestrictions() {
	if raw := argumentValue("--allowed-uid"); raw != "" {
		if value, err := strconv.ParseInt(raw, 10, 32); err == nil && value >= 0 {
			allowedClientUID = int32(value)
		} else {
			logf("ignoring invalid --allowed-uid %q", raw)
		}
	}
	if sid := argumentValue("--allowed-sid"); sid != "" {
		// Only accept a numeric SID: it is pasted straight into the pipe DACL.
		if strings.HasPrefix(sid, "S-1-5-") && isNumericSID(sid) {
			allowedClientSID = sid
		} else {
			logf("ignoring invalid --allowed-sid %q", sid)
		}
	}
}

// isNumericSID reports whether value looks like "S-1-5-21-<digits>" with no
// unexpected characters.
func isNumericSID(value string) bool {
	for _, part := range strings.Split(strings.TrimPrefix(value, "S-1-5-"), "-") {
		if part == "" {
			return false
		}
		for _, char := range part {
			if char < '0' || char > '9' {
				return false
			}
		}
	}
	return true
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

// desktopHost is the desktop side of the shared control API: it owns the
// whole core lifecycle, which a tunnel process leaves to its platform.
type desktopHost struct{}

func (desktopHost) Version() string { return serviceVersion }

func (desktopHost) Runtime() map[string]string { return clashRuntimeInfo() }

func (desktopHost) Path() (string, error) { return os.Executable() }

func (desktopHost) Env() map[string]string {
	env := make(map[string]string)
	for _, entry := range os.Environ() {
		if key, value, found := strings.Cut(entry, "="); found {
			env[key] = value
		}
	}
	return env
}

func (desktopHost) Memory() any { return memorySnapshot() }

func (desktopHost) Status() (bool, bool) { return core.status() }

func (desktopHost) Start(body any, vpn bool) *Response { return startProfile(body, vpn) }

func (desktopHost) StartCore(body any) *Response { return startCoreProfile(body) }

func (desktopHost) CoreStarted() bool { return core.isStarted() }

func (desktopHost) StopVPN() *Response { return stopVpn() }

func (desktopHost) Reload() *Response { return reloadConfig() }

func (desktopHost) Stop() *Response { return stopProxy() }

func (desktopHost) StopCore() *Response { return stopClash() }

// Profiles keeps only the profile metadata that drives the desktop UI; the
// schedule and the download itself belong to the shared profile API.
func (desktopHost) Profiles() ProfileHooks {
	return ProfileHooks{
		Dir: func(*http.Request) string { return core.runtimeConfigDir() },
		Store: func(body map[string]any, dir string) {
			profile := parseProfile(body)
			if profile == nil {
				return
			}
			core.updateProfile(profile)
			if err := core.commitAPIState(profile, core.desiredVpnEnabled()); err != nil {
				logf("save Clash state failed: %v", err)
			}
		},
		Apply: core.applyRefreshedConfig,
	}
}

// serve runs the control API until ctx is cancelled. ready, when not nil, is
// closed once the IPC endpoint is accepting connections.
func serve(ctx context.Context, ready chan<- struct{}) error {
	parseAccessRestrictions()
	core.initialize()
	go watchWake(ctx)

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
	ServeHTTP(w, r, Route(desktopHost{}, logf), logf)
}

// ------------------------------------------------------------- API handlers

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

// ------------------------------------------------------------- API handlers

func startProfile(data any, vpnEnabled bool) *Response {
	profile := parseProfile(data)
	if profile == nil || profile.ConfigDir == "" {
		// 托盘没有 profile 数据，只能用上一次持久化的那份来开代理。
		profile = core.apiProfileSnapshot()
	}
	if profile == nil || profile.ConfigDir == "" {
		return Error("invalid profile")
	}

	if err := core.run(profile.ConfigDir, vpnEnabled); err != nil {
		return Error(err.Error())
	}
	core.setProfile(profile)
	if err := core.commitAPIState(profile, vpnEnabled); err != nil {
		return Error("save Clash state failed: " + err.Error())
	}
	return OK(nil)
}

// applyRefreshedConfig restarts the core so it reads the config the shared
// API just wrote, restoring config.yaml.bak when the restart rejects it.
func (c *coreRuntime) applyRefreshedConfig(dir string) error {
	configPath := filepath.Join(dir, configFileName)
	backupPath := configPath + ".bak"

	c.mu.Lock()
	vpnEnabled := c.desiredVPN
	restart := c.started && c.configDir == dir
	var restartErr error
	if restart {
		restartErr = c.restartLocked(dir, vpnEnabled)
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
	if restored, err := os.ReadFile(backupPath); err == nil {
		if err := os.WriteFile(configPath, restored, 0o644); err != nil {
			logf("restore previous config failed: %v", err)
		}
	}
	_ = os.Remove(backupPath)

	c.mu.Lock()
	var restoreErr error
	if c.configDir == dir {
		restoreErr = c.restartLocked(dir, vpnEnabled)
	}
	c.mu.Unlock()
	if restoreErr != nil {
		logf("restore previous config failed: %v", restoreErr)
	}
	return restartErr
}

func stopVpn() *Response {
	if err := core.disableProxy(); err != nil {
		return Error(err.Error())
	}

	configDir := core.apiConfigDir()
	if configDir == "" {
		configDir = core.runtimeConfigDir()
	}
	if configDir != "" {
		if err := core.commitAPIState(core.apiProfileSnapshot(), false); err != nil {
			return Error("save Clash state failed: " + err.Error())
		}
	}
	return OK(nil)
}

func reloadConfig() *Response {
	if err := core.reload(); err != nil {
		return Error(err.Error())
	}
	return OK(nil)
}

// stopProxy 是「关代理」：撤掉 TUN 与所有入站监听，内核和控制器保持运行，
// /proxies、/configs 等 API 继续可用，之后 startVpn 能直接重新监听端口。
func stopProxy() *Response {
	if err := core.disableProxy(); err != nil {
		return Error(err.Error())
	}
	return OK(nil)
}

// stopClash 是「停内核」：先撤代理（TUN + 入站监听），再真正结束内核、
// 释放 profile 与刷新定时器。服务进程本身仍在，下次 startCore 还能再起。
func stopClash() *Response {
	if err := core.disableProxy(); err != nil {
		return Error(err.Error())
	}
	if err := core.stop(); err != nil {
		return Error(err.Error())
	}
	if err := core.clearAPIState(); err != nil {
		return Error("clear Clash state failed: " + err.Error())
	}
	return OK(nil)
}

// startCoreProfile 是「起内核」：内核与控制器就绪（/proxies 可用），但不监听
// 入站端口，也不装 TUN。开代理交给 startVpn。
func startCoreProfile(data any) *Response {
	profile := parseProfile(data)
	if profile == nil || profile.ConfigDir == "" {
		return Error("invalid profile")
	}

	if err := core.run(profile.ConfigDir, false); err != nil {
		return Error(err.Error())
	}
	core.setProfile(profile)
	if err := core.disableProxy(); err != nil {
		return Error(err.Error())
	}
	if err := core.commitAPIState(profile, false); err != nil {
		return Error("save Clash state failed: " + err.Error())
	}
	return OK(nil)
}

// ------------------------------------------------------ profile and scheduling

// clashProfile is the JSON shape the app sends and the state file stores.
type clashProfile struct {
	ConfigDir string `json:"configDir"`
	ID        string `json:"id,omitempty"`
	Name      string `json:"name,omitempty"`
	URL       string `json:"url,omitempty"`
	// Script is the profile's JavaScript transform. The service runs it itself
	// (see internal/profilerefresh) so a subscription refresh started by the
	// daemon produces the same config the app would.
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

// nextUpdateDelay reports when this profile is refreshed again. The rule (and
// the floor that keeps a fresh start from downloading immediately) lives in
// internal/profileschedule so the desktop daemon, the mobile services and the
// app all wait the same time. A profile the app never downloaded has no
// schedule here, matching `ClashProfile.nextUpdateDelay`.
func (p *clashProfile) nextUpdateDelay(now time.Time) (time.Duration, bool) {
	last, ok := parseProfileTime(p.UpdateTime)
	if !ok {
		return 0, false
	}
	return profileschedule.Delay(now, last, p.UpdateInterval, profileschedule.DesktopSettleDelay)
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
	value, ok := data.(map[string]any)
	if !ok {
		return nil
	}
	payload, err := json.Marshal(value)
	if err != nil {
		return nil
	}
	var profile clashProfile
	if err := json.Unmarshal(payload, &profile); err != nil {
		return nil
	}
	return &profile
}

// ------------------------------------------------------------- core runtime

// Run starts the desktop daemon; each OS file implements runPlatformService.
func Run() {
	runPlatformService()
}

var core = newCoreRuntime()

type coreRuntime struct {
	mu sync.Mutex

	statePath string

	// Observed runtime state, changed only by native start/stop operations.
	started bool
	// proxyActive 表示入站监听（mixed 等）是否在跑。started 只说明内核与控制器
	// 是否胜任；关闭代理后 proxyActive=false 而 started 仍为 true，/proxies 等
	// 控制器 API 继续可用。
	proxyActive  bool
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

// stateFilePath is the persisted "desired state" file. The service is
// system-wide on every desktop platform (root LaunchDaemon, LocalSystem service,
// systemd system unit), so the file lives in a machine-wide directory instead of
// the per-user profile: a privileged process must never write into a directory
// the invoking user can rewrite.
func stateFilePath() (string, error) {
	if runtime.GOOS == "darwin" {
		return filepath.Join("/Library", "Application Support", "Clashy", stateFileName), nil
	}
	if runtime.GOOS == "windows" {
		if programData := os.Getenv("ProgramData"); programData != "" {
			return filepath.Join(programData, "Clashy", stateFileName), nil
		}
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

// isStarted 报告内核是否在跑（started 只说明内核胜任，不代表代理开着）。
func (c *coreRuntime) isStarted() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.started
}

func (c *coreRuntime) status() (running bool, vpnEnabled bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.proxyActive, c.runtimeVPN
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

// disableProxy 关闭 TUN 与所有入站监听，但保留内核和控制器：stop 的语义是
// 「代理关了」，不是「core 停了」，停止后 /proxies 等 API 仍然可用。
func (c *coreRuntime) disableProxy() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.disableProxyLocked()
}

func (c *coreRuntime) disableProxyLocked() error {
	if !c.started {
		return nil
	}
	if err := resetTunListener(); err != nil {
		return err
	}
	CloseInboundListeners()
	c.proxyActive = false
	c.runtimeVPN = false
	return nil
}

func (c *coreRuntime) reload() error {
	c.mu.Lock()
	defer c.mu.Unlock()

	if !c.started || c.configDir == "" {
		return errors.New("Clash core is not running")
	}
	// 代理关着时没有需要重放的东西：重放配置会把入站端口重新打开，
	// 与「关闭代理后端口不监听」的语义冲突。
	if !c.proxyActive {
		return nil
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
// stop 结束内核并丢掉 profile / 刷新定时器；服务进程与控制器随之关闭。
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
	c.mirrorScheduleLocked()
	c.scheduleProfileUpdateLocked()
}

// mirrorScheduleLocked writes the refresh schedule to the state file the
// control API reads, so GET /clash/schedule answers the same on desktop as in a
// tunnel process. The desktop timer below stays the owner of when it fires; both
// sides use the rule in internal/profileschedule.
func (c *coreRuntime) mirrorScheduleLocked() {
	if c.profile == nil || c.profile.ConfigDir == "" {
		return
	}
	last := int64(0)
	if updated, ok := parseProfileTime(c.profile.UpdateTime); ok {
		last = updated.UnixMilli()
	}
	var schedule *profileschedule.Schedule
	if c.profile.URL != "" && c.profile.UpdateInterval > 0 {
		schedule = &profileschedule.Schedule{
			URL:             c.profile.URL,
			Script:          c.profile.Script,
			IntervalMinutes: c.profile.UpdateInterval,
			LastUpdateMs:    last,
		}
	}
	if err := profileschedule.Save(c.profile.ConfigDir, schedule); err != nil {
		logf("write profile schedule: %v", err)
	}
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
	if c.configDir == configDir && c.started && c.proxyActive && c.runtimeVPN == vpnEnabled {
		return nil
	}

	// The daemon itself is privileged on every desktop platform, so it creates the
	// TUN interface in-process instead of asking a helper for it.

	var interfacesBefore []string
	if runtime.GOOS == "darwin" {
		interfacesBefore, _ = listTunInterfaces()
	}

	c.started = false
	c.runtimeVPN = false
	err := startEngine(configDir, vpnEnabled)

	c.configDir = configDir
	c.started = err == nil && engineStarted()
	c.proxyActive = c.started
	c.runtimeVPN = c.started && vpnEnabled
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
		// Linux and Windows use the fixed device name we ask sing-tun for.
		c.tunInterface = defaultTunDevice
	}
	return nil
}

func (c *coreRuntime) stopLocked() error {
	err := stopEngine()
	c.started = engineStarted()
	c.proxyActive = false
	if !c.started {
		c.configDir = ""
		c.runtimeVPN = false
		// 停下之后把堆里的空闲页还给系统：这个进程长期驻留，Go 默认只是把页
		// 留着复用，macOS 上看起来就是「关掉 VPN 了内存还不降」。
		debug.FreeOSMemory()
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
	started bool
	tun     *sing_tun.Listener
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
	// mihomo downloads a missing GeoIP/GeoSite database while parsing rules and
	// aborts the parse when that download fails; fetch it up front instead.
	geoensure.Ensure(filepath.Join(abs, configFileName))
	return nil
}

// startEngine applies configDir/config.yaml. With vpnEnabled it also brings up
// the TUN interface; without it only the proxy listeners and the controller run.
// ensureConfigFile rejects a config.yaml that is a symlink or not a regular file:
// the daemon runs privileged, so the path it follows must be the real file inside
// the configuration directory.
func ensureConfigFile(configDir string) error {
	path := filepath.Join(configDir, configFileName)
	info, err := os.Lstat(path)
	if err != nil {
		return fmt.Errorf("read config file: %w", err)
	}
	if info.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("refusing to load a symlinked config file: %s", path)
	}
	if !info.Mode().IsRegular() {
		return fmt.Errorf("config file is not a regular file: %s", path)
	}
	return nil
}

func startEngine(configDir string, vpnEnabled bool) error {
	if err := setHomeDir(configDir); err != nil {
		return err
	}
	// A privileged process must not be steered through a symlink planted in a
	// user-writable directory.
	if err := ensureConfigFile(configDir); err != nil {
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

	// mihomo itself must not create the tunnel: the listener below is created
	// explicitly so that both the stack and the interface options stay under our
	// control (gvisor stack, our device name, our addresses).
	cfg.General.Tun.Enable = false
	hub.ApplyConfig(cfg)

	if !vpnEnabled {
		engine.started = true
		return nil
	}

	tunListener, err := sing_tun.New(desktopTunOptions(cfg), tunnel.Tunnel)
	if err != nil {
		executor.Shutdown()
		return fmt.Errorf("start tun: %w", err)
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
	if engine.started {
		// 只关 TUN 会把这一轮配置的规则、代理和 inbound listener 全留在内存里：
		// 实测 reload 一次堆就多出约 100MB 且不再回收。Shutdown 会关掉 listener、
		// 清 resolver/tproxy，下一次 ApplyConfig 再整体重建。
		executor.Shutdown()
	}
	// mihomo 的 Shutdown 只关 TUN（listener.Cleanup 只 close 了 tun listener），
	// 它的 CLI 靠进程退出收掉 inbound。桌面服务和移动端 app 都是常驻进程，
	// 不显式关闭的话 mixed 端口在 stop() 之后仍在 listen。
	CloseInboundListeners()
	engine.started = false
	return nil
}

// CloseInboundListeners 关掉 executor.Shutdown() 之后仍然存活的入站监听：
// mixed/http/socks/redir/tproxy/ss/vmess/tuic，以及 config 里 `listeners:` 那批。
// 用各 ReCreate* 的「0 端口 / 空配置」入口关闭，这样不必改 mihomo 子模块。
// 桌面服务（clashService）和移动端 C API（libclash 的 stop）共用这一份，
// 三端行为保持一致。
func CloseInboundListeners() {
	mihomoListener.ReCreateMixed(0, tunnel.Tunnel)
	mihomoListener.ReCreateHTTP(0, tunnel.Tunnel)
	mihomoListener.ReCreateSocks(0, tunnel.Tunnel)
	mihomoListener.ReCreateRedir(0, tunnel.Tunnel)
	mihomoListener.ReCreateTProxy(0, tunnel.Tunnel)
	mihomoListener.ReCreateShadowSocks("", tunnel.Tunnel)
	mihomoListener.ReCreateVmess("", tunnel.Tunnel)
	mihomoListener.ReCreateTuic(LC.TuicServer{}, tunnel.Tunnel)
	// 空映射 + dropOld 会把 `listeners:` 注册的 inbound 全部 Close 掉。
	mihomoListener.PatchInboundListeners(nil, tunnel.Tunnel, true)
	// DNS 服务（config 里的 dns.listen）同样挂在执行器之外，Shutdown 不会关它；
	// 传空地址会把已建的 TCP/UDP DNS 监听一起 Shutdown。
	mihomoDNS.ReCreateServer("", nil, nil)
}

func resetTunListener() error {
	var errs []error

	// Stop mihomo's readers before the device disappears.
	if engine.tun != nil {
		if err := engine.tun.Close(); err != nil {
			errs = append(errs, err)
		}
		engine.tun = nil
	}
	// ReCreateTun clears mihomo's cached TUN configuration.
	mihomoListener.ReCreateTun(LC.Tun{}, tunnel.Tunnel)
	return errors.Join(errs...)
}

// desktopTunOptions builds the listener options for the TUN interface this
// privileged daemon creates itself.
func desktopTunOptions(cfg *config.Config) LC.Tun {
	stack := cfg.General.Tun.Stack
	if stack.String() == "unknown" {
		stack = constant.TunGvisor
	}

	mtu := cfg.General.Tun.MTU
	if mtu == 0 {
		mtu = 9000
	}

	device := cfg.General.Tun.Device
	if device == "" {
		device = defaultTunDevice
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
		AutoRoute:                true,
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
	}
}

const (
	defaultTunDevice = "clashy"

	defaultInet4Address = "172.19.0.1/30"
	defaultInet6Address = "fdfe:dcba:9876::1/126"
	defaultDNSHijack    = "172.19.0.2:53"
)

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

	// apiProfile 留在内存里：托盘没有 profile，停掉之后再点「启动」要靠它
	// 把内核重新拉起来。重启服务进程后才会真正丢掉。
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
		c.mirrorScheduleLocked()
		c.scheduleProfileUpdateLocked()
		return
	}
	c.profile = target.withUpdateTime(time.Now())
	c.mirrorScheduleLocked()
	c.scheduleProfileUpdateLocked()
	logf("profile updated: %s", target.displayName())
}

// refreshConfig downloads the subscription and restarts the core with the
// refreshed config. The previous config file is restored when the restart
// fails.
//
// The download, the profile script and the overlay of app-owned keys live in
// internal/profilerefresh, the same code the mobile runtimes use: the script
// runs on the downloaded config first and the app's own settings (mode,
// mixed-port, tun, dns, ...) are applied on top, so they win over anything the
// script produced.
func (c *coreRuntime) refreshConfig(profile *clashProfile) error {
	if err := profilerefresh.RefreshFile(profile.ConfigDir, profile.URL, profile.Script); err != nil {
		return err
	}
	return c.applyRefreshedConfig(profile.ConfigDir)
}

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

// watchWake 在系统睡眠唤醒后把空闲堆还给操作系统。睡眠期间进程被挂起，唤醒后
// Go 只是把页留着复用，活动监视器看到的就是内存长期高位（实测唤醒后能到 300MB）。
// 用墙上时钟和定时器周期的差判断「睡过一觉」，比接各平台的唤醒通知简单，三平台
// 也一致：定时器暂停期间墙上时钟照样前进，唤醒后的第一个 tick 就能看出缺口。
func watchWake(ctx context.Context) {
	const interval = 20 * time.Second
	lastWall := time.Now().UnixNano()
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			now := time.Now().UnixNano()
			gap := time.Duration(now - lastWall)
			lastWall = now
			if gap <= 2*interval {
				continue
			}
			debug.FreeOSMemory()
			logf("reclaimed memory after %s pause", gap.Round(time.Second))
		}
	}
}

// memorySnapshot reports what a long-lived daemon is actually holding: goroutine
// count is the cheap signal for "every reload leaks a listener", heap numbers
// distinguish idle-but-retained pages from real retention.
type memorySnapshotData struct {
	Goroutines int    `json:"goroutines"`
	HeapInuse  uint64 `json:"heapInuse"`
	HeapAlloc  uint64 `json:"heapAlloc"`
	HeapSys    uint64 `json:"heapSys"`
	StackInuse uint64 `json:"stackInuse"`
}

func memorySnapshot() memorySnapshotData {
	var stats runtime.MemStats
	runtime.ReadMemStats(&stats)
	return memorySnapshotData{
		Goroutines: runtime.NumGoroutine(),
		HeapInuse:  stats.HeapInuse,
		HeapAlloc:  stats.HeapAlloc,
		HeapSys:    stats.HeapSys,
		StackInuse: stats.StackInuse,
	}
}

func logf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "%s %s\n", time.Now().Format("15:04:05"), fmt.Sprintf(format, args...))
}

// SocketName is the control socket a tunnel process serves inside configDir.
//
// The name is short on purpose: `sockaddr_un` caps the whole path at 104 bytes
// on Darwin, and the iOS App Group container already eats most of that budget.
const SocketName = "cs.sock"

// maxSocketPath is the `sockaddr_un.sun_path` budget on Darwin. Unix sockets
// elsewhere allow more, but keeping one rule means the app and the core always
// agree on where the socket is.
const maxSocketPath = 100

// SocketPath returns the control socket of a config directory.
//
// A path that would not fit the Darwin budget moves one level up: the iOS App
// Group container prefix alone can leave a handful of bytes, while the parent
// of the config directory is still private to the same process.
func SocketPath(configDir string) string {
	path := filepath.Join(configDir, SocketName)
	if len(path) <= maxSocketPath {
		return path
	}
	parent := filepath.Dir(configDir)
	return filepath.Join(parent, SocketName)
}

// Routes of the control API. The desktop daemon answers all of them, a tunnel
// process only the profile ones.
const (
	RootPath         = "/"
	VersionPath      = "/version"
	PathPath         = "/baseInfo/path"
	MemPath          = "/baseInfo/mem"
	EnvPath          = "/baseInfo/env"
	ClashPath        = "/clash"
	StatusPath       = "/clash/status"
	VPNStatusPath    = "/clash/vpn/status"
	CorePath         = "/clash/core"
	CoreStatusPath   = "/clash/core/status"
	VPNStartPath     = "/clash/vpn/start"
	VPNStopPath      = "/clash/vpn/stop"
	ReloadPath       = "/clash/reload"
	ProfilePath      = "/clash/profile"
	RefreshPath      = "/clash/refresh"
	SchedulePath     = "/clash/schedule"
	StopPath         = "/clash/stop"
	CoreStopPath     = "/clash/core/stop"
	maxRequestBody   = 8 << 20
	maxProfileBody   = 1 << 20
	apiErrorCode     = 1001
	greetingResponse = "Clash VPN!"
)

// Response is the `{code,msg,data}` envelope every host answers with.
type Response struct {
	Code int    `json:"code"`
	Msg  string `json:"msg"`
	Data any    `json:"data"`
}

// OK builds a successful response.
func OK(data any) *Response { return &Response{Code: 0, Data: data} }

// Error builds a failed response with the code the app understands.
func Error(message string) *Response { return &Response{Code: apiErrorCode, Msg: message} }

// RouteFunc dispatches one request into the shared envelope.
type RouteFunc func(w http.ResponseWriter, r *http.Request) (*Response, int)

// Host is what the shared router needs from a runtime.
//
// The desktop daemon implements every method; a tunnel process implements the
// profile half and returns ErrUnsupported for the rest.
type Host interface {
	// Version is the service version the app compares before reinstalling.
	Version() string
	// Runtime feeds GET /clash: where the service runs from.
	Runtime() map[string]string
	// Path is the resolved executable.
	Path() (string, error)
	// Env is the process environment.
	Env() map[string]string
	// Memory feeds GET /baseInfo/mem.
	Memory() any
	// Status reports whether the core runs and whether the tunnel is up.
	Status() (started bool, vpn bool)
	// Start 开代理：起内核并装 TUN。
	Start(body any, vpn bool) *Response
	// StartCore 只起内核：控制器可用，不装 TUN、不监听入站端口。
	StartCore(body any) *Response
	// CoreStarted 报告内核与控制器是否在跑，与代理是否开着无关。
	CoreStarted() bool
	StopVPN() *Response
	Reload() *Response
	// Stop 关代理：撤 TUN、关入站监听，内核与控制器继续可用。
	Stop() *Response
	// StopCore 停内核：代理也一起关，/proxies 等 API 不再应答。
	StopCore() *Response
	// Profiles is the profile API's bookkeeping for this host.
	Profiles() ProfileHooks
}

// Route is the single route table of the control API.
func Route(h Host, logf func(format string, args ...any)) RouteFunc {
	return func(w http.ResponseWriter, r *http.Request) (*Response, int) {
		switch r.URL.Path {
		case RootPath:
			if r.Method != http.MethodGet {
				return nil, http.StatusMethodNotAllowed
			}
			return OK(greetingResponse), http.StatusOK

		case VersionPath:
			if r.Method != http.MethodGet {
				return nil, http.StatusMethodNotAllowed
			}
			return OK(h.Version()), http.StatusOK

		case PathPath:
			if r.Method != http.MethodGet {
				return nil, http.StatusMethodNotAllowed
			}
			path, err := h.Path()
			if err != nil {
				return Error(err.Error()), http.StatusOK
			}
			return OK(path), http.StatusOK

		case MemPath:
			if r.Method != http.MethodGet {
				return nil, http.StatusMethodNotAllowed
			}
			return OK(h.Memory()), http.StatusOK

		case EnvPath:
			if r.Method != http.MethodGet {
				return nil, http.StatusMethodNotAllowed
			}
			return OK(h.Env()), http.StatusOK

		case ClashPath:
			if r.Method == http.MethodGet {
				return OK(h.Runtime()), http.StatusOK
			}
			if r.Method != http.MethodPost {
				return nil, http.StatusMethodNotAllowed
			}
			data, res := readBody(r)
			if res != nil {
				return res, http.StatusOK
			}
			return h.Start(data, true), http.StatusOK

		case CoreStatusPath:
			if r.Method != http.MethodGet {
				return nil, http.StatusMethodNotAllowed
			}
			return OK(h.CoreStarted()), http.StatusOK

		case StatusPath:
			if r.Method != http.MethodGet {
				return nil, http.StatusMethodNotAllowed
			}
			started, _ := h.Status()
			return OK(started), http.StatusOK

		case VPNStatusPath:
			if r.Method != http.MethodGet {
				return nil, http.StatusMethodNotAllowed
			}
			_, vpn := h.Status()
			return OK(vpn), http.StatusOK

		case CorePath, VPNStartPath:
			if r.Method != http.MethodPost {
				return nil, http.StatusMethodNotAllowed
			}
			data, res := readBody(r)
			if res != nil {
				return res, http.StatusOK
			}
			// `/clash` and `/clash/vpn/start` 开代理（TUN + 入站端口）；
			// `/clash/core` 只起内核：控制器可用但不监听端口。
			if r.URL.Path == CorePath {
				return h.StartCore(data), http.StatusOK
			}
			return h.Start(data, true), http.StatusOK

		case VPNStopPath:
			if r.Method != http.MethodPost {
				return nil, http.StatusMethodNotAllowed
			}
			return h.StopVPN(), http.StatusOK

		case ReloadPath:
			if r.Method != http.MethodPost {
				return nil, http.StatusMethodNotAllowed
			}
			return h.Reload(), http.StatusOK

		case ProfilePath:
			return handleProfileRoute(r, h.Profiles(), logf)

		case RefreshPath:
			return handleRefreshRoute(r, h.Profiles(), logf)

		case SchedulePath:
			return handleScheduleRoute(r, h.Profiles())

		case CoreStopPath:
			if r.Method != http.MethodPost {
				return nil, http.StatusMethodNotAllowed
			}
			return h.StopCore(), http.StatusOK

		case StopPath:
			if r.Method != http.MethodPost {
				return nil, http.StatusMethodNotAllowed
			}
			return h.Stop(), http.StatusOK
		}

		return nil, http.StatusNotFound
	}
}

// readBody applies the JSON middleware of the retired Dart server: only
// `application/json` bodies are accepted and a body that is not valid JSON is
// rejected.
func readBody(r *http.Request) (any, *Response) {
	if contentType := r.Header.Get("Content-Type"); contentType != "" &&
		!strings.HasPrefix(contentType, "application/json") {
		return nil, Error("content-type != application/json")
	}

	payload, err := io.ReadAll(io.LimitReader(r.Body, maxRequestBody))
	if err != nil {
		return nil, Error(err.Error())
	}
	if len(payload) == 0 {
		return "", nil
	}

	var data any
	if err := json.Unmarshal(payload, &data); err != nil {
		return nil, Error("invalid json body")
	}
	return data, nil
}

// ServeHTTP runs one request through the shared envelope, panic guard and
// logging. Every host uses this; only the Host differs.
func ServeHTTP(
	w http.ResponseWriter,
	r *http.Request,
	route RouteFunc,
	logf func(format string, args ...any),
) {
	started := time.Now()
	res, status := safeRoute(w, r, route, logf)

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

func safeRoute(
	w http.ResponseWriter,
	r *http.Request,
	route RouteFunc,
	logf func(format string, args ...any),
) (res *Response, status int) {
	defer func() {
		if recovered := recover(); recovered != nil {
			logf("panic while handling %s %s: %v", r.Method, r.URL.Path, recovered)
			res, status = Error(fmt.Sprint(recovered)), http.StatusOK
		}
	}()
	return route(w, r)
}

// ProfileHooks lets a host keep its own profile bookkeeping while the profile
// routes stay here. A tunnel process passes Dir/Apply/OnSchedule; the desktop
// daemon uses Store to persist the profile name/id it shows in the UI.
type ProfileHooks struct {
	// Dir resolves the config directory of a request; nil keeps the body's.
	Dir func(r *http.Request) string
	// Store receives the raw profile body and the resolved directory.
	Store func(body map[string]any, dir string)
	// Apply loads the refreshed config into the running core.
	Apply func(dir string) error
	// OnSchedule tells the host's timer that the stored schedule changed.
	OnSchedule func()
}

func (h ProfileHooks) dir(r *http.Request) string {
	if h.Dir == nil {
		return ""
	}
	return h.Dir(r)
}

func (h ProfileHooks) scheduleChanged() {
	if h.OnSchedule != nil {
		h.OnSchedule()
	}
}

func (h ProfileHooks) applyConfig(dir string) error {
	if h.Apply == nil {
		return nil
	}
	return h.Apply(dir)
}

// refreshMu keeps two refreshes from downloading at the same time: the
// schedule file is written atomically, but a duplicate download would still
// waste the provider's bandwidth.
var refreshMu sync.Mutex

// profileRequest is the `ClashProfile` the app already builds for the desktop
// daemon: the refresh interval is `updateInterval` in minutes.
type profileRequest struct {
	URL            string `json:"url"`
	Script         string `json:"script"`
	UpdateInterval int    `json:"updateInterval"`
	UpdateTime     any    `json:"updateTime"`
}

func handleProfileRoute(r *http.Request, hooks ProfileHooks, logf func(format string, args ...any)) (*Response, int) {
	if r.Method != http.MethodPost {
		return nil, http.StatusMethodNotAllowed
	}
	defer r.Body.Close()

	dir := hooks.dir(r)
	payload, err := io.ReadAll(io.LimitReader(r.Body, maxProfileBody))
	if err != nil {
		return Error("read profile: " + err.Error()), http.StatusBadRequest
	}

	var request profileRequest
	if err := json.Unmarshal(payload, &request); err != nil {
		return Error("invalid profile: " + err.Error()), http.StatusBadRequest
	}
	if hooks.Store != nil {
		var body map[string]any
		if json.Unmarshal(payload, &body) == nil && body != nil {
			hooks.Store(body, dir)
			if configDir, ok := body["configDir"].(string); ok && configDir != "" {
				dir = configDir
			}
		}
	}
	if dir == "" {
		return Error("config dir is empty"), http.StatusOK
	}

	schedule := &profileschedule.Schedule{
		URL:             strings.TrimSpace(request.URL),
		Script:          request.Script,
		IntervalMinutes: request.UpdateInterval,
		LastUpdateMs:    parseUpdateTime(request.UpdateTime),
	}
	if !schedule.Scheduled() {
		// A profile without a url or interval is still a valid selection: drop
		// the schedule so the tunnel stops downloading on its own.
		if err := profileschedule.Save(dir, nil); err != nil {
			return Error(err.Error()), http.StatusOK
		}
		hooks.scheduleChanged()
		return OK(nextDelayPayload(dir)), http.StatusOK
	}
	if err := profileschedule.Save(dir, schedule); err != nil {
		return Error(err.Error()), http.StatusOK
	}
	hooks.scheduleChanged()

	// ?refresh=false stores the profile for the next scheduled download only;
	// the app uses it when it already wrote config.yaml itself.
	if r.URL.Query().Get("refresh") == "false" {
		return OK(nextDelayPayload(dir)), http.StatusOK
	}

	if err := refreshProfile(dir, schedule); err != nil {
		logf("profile refresh failed: %v", err)
		return Error(err.Error()), http.StatusOK
	}
	if err := hooks.applyConfig(dir); err != nil {
		logf("apply profile config: %v", err)
		return Error(err.Error()), http.StatusOK
	}
	return OK(nextDelayPayload(dir)), http.StatusOK
}

func handleRefreshRoute(r *http.Request, hooks ProfileHooks, logf func(format string, args ...any)) (*Response, int) {
	if r.Method != http.MethodPost {
		return nil, http.StatusMethodNotAllowed
	}
	defer r.Body.Close()

	dir := hooks.dir(r)
	if dir == "" {
		return Error("config dir is empty"), http.StatusOK
	}
	schedule, err := profileschedule.Load(dir)
	if err != nil {
		return Error(err.Error()), http.StatusOK
	}
	if !schedule.Scheduled() {
		return Error("profile schedule is empty"), http.StatusOK
	}
	if err := refreshProfile(dir, schedule); err != nil {
		logf("scheduled profile refresh failed: %v", err)
		return Error(err.Error()), http.StatusOK
	}
	if err := hooks.applyConfig(dir); err != nil {
		logf("apply profile config: %v", err)
		return Error(err.Error()), http.StatusOK
	}
	return OK(nextDelayPayload(dir)), http.StatusOK
}

func handleScheduleRoute(r *http.Request, hooks ProfileHooks) (*Response, int) {
	if r.Method != http.MethodGet {
		return nil, http.StatusMethodNotAllowed
	}
	dir := hooks.dir(r)
	if dir == "" {
		return Error("config dir is empty"), http.StatusOK
	}
	schedule, err := profileschedule.Load(dir)
	if err != nil {
		return Error(err.Error()), http.StatusOK
	}
	return OK(schedulePayload(schedule)), http.StatusOK
}

// refreshProfile downloads the subscription of schedule, rewrites config.yaml
// and records the attempt. A failed download still counts as an attempt, so the
// next one waits a full interval instead of retrying in a tight loop.
func refreshProfile(configDir string, schedule *profileschedule.Schedule) error {
	refreshMu.Lock()
	defer refreshMu.Unlock()

	refreshErr := profilerefresh.RefreshFile(configDir, schedule.URL, schedule.Script)

	schedule.LastUpdateMs = time.Now().UnixMilli()
	if err := profileschedule.Save(configDir, schedule); err != nil && refreshErr == nil {
		return err
	}
	return refreshErr
}

// listenSocket serves the API on `<configDir>/cs.sock`; the caller closes the
// listener when the host stops. The socket is created 0600, so only the app and
// the extension sharing the directory can reach it.
func listenSocket(configDir string) (net.Listener, error) {
	path := SocketPath(configDir)
	if err := os.MkdirAll(configDir, 0o755); err != nil {
		return nil, fmt.Errorf("create config dir: %w", err)
	}
	// A socket left behind by a killed process makes Listen fail, and the name
	// belongs to this API, so a stale one is always safe to remove.
	if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
		return nil, fmt.Errorf("remove stale control socket: %w", err)
	}

	listener, err := net.Listen("unix", path)
	if err != nil {
		return nil, fmt.Errorf("listen on control socket: %w", err)
	}
	if err := os.Chmod(path, 0o600); err != nil {
		_ = listener.Close()
		return nil, fmt.Errorf("restrict control socket: %w", err)
	}
	return listener, nil
}

// schedulePayload is the `data` of /clash/schedule and of every refresh response:
// the app and the platform timers only need `nextDelayMs` (-1 = no schedule).
func schedulePayload(schedule *profileschedule.Schedule) map[string]any {
	if schedule == nil {
		return map[string]any{"scheduled": false, "nextDelayMs": int64(-1)}
	}
	delay, ok := schedule.Delay(time.Now(), profileschedule.SettleDelay)
	return map[string]any{
		"scheduled":   schedule.Scheduled(),
		"url":         schedule.URL,
		"interval":    schedule.IntervalMinutes,
		"lastUpdate":  schedule.LastUpdateMs,
		"nextDelayMs": delayMilliseconds(delay, ok),
	}
}

func nextDelayPayload(configDir string) map[string]any {
	schedule, err := profileschedule.Load(configDir)
	if err != nil {
		return map[string]any{"scheduled": false, "nextDelayMs": int64(-1)}
	}
	return schedulePayload(schedule)
}

func delayMilliseconds(delay time.Duration, ok bool) int64 {
	if !ok {
		return -1
	}
	if delay <= 0 {
		return 0
	}
	return delay.Milliseconds()
}

// parseUpdateTime accepts what the app writes: an ISO-8601 string (Dart's
// `toIso8601String`) or a millisecond number. Anything else counts as "never
// downloaded".
func parseUpdateTime(value any) int64 {
	switch typed := value.(type) {
	case string:
		if typed == "" {
			return 0
		}
		for _, layout := range []string{time.RFC3339Nano, "2006-01-02T15:04:05.999999999"} {
			parsed, err := time.ParseInLocation(layout, typed, time.Local)
			if err == nil {
				return parsed.UnixMilli()
			}
		}
		return 0
	case float64:
		return int64(typed)
	case json.Number:
		milliseconds, err := typed.Int64()
		if err != nil {
			return 0
		}
		return milliseconds
	case int64:
		return typed
	case int:
		return int64(typed)
	default:
		return 0
	}
}

func writeOK(w http.ResponseWriter, data any) {
	writeEnvelope(w, http.StatusOK, 0, "", data)
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeEnvelope(w, status, apiErrorCode, message, nil)
}

func writeEnvelope(w http.ResponseWriter, status int, code int, message string, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	payload, err := json.Marshal(map[string]any{"code": code, "msg": message, "data": data})
	if err != nil {
		return
	}
	_, _ = w.Write(payload)
}

// ------------------------------------------------------- tunnel profile API

// Server serves the profile API from inside a tunnel process, where the
// platform starts the core and this only refreshes the subscription and applies
// config.yaml to it. The desktop daemon does not use it: it owns the whole
// lifecycle and serves every route itself.
type Server struct {
	dir       string
	listener  net.Listener
	server    *http.Server
	scheduler *profilescheduler.Scheduler
	mu        sync.Mutex
}

// ServeTunnel exposes `<configDir>/cs.sock` with the profile routes. apply
// loads the refreshed config into the running core; it must not hold a lock the
// caller takes later.
func ServeTunnel(configDir string, apply func(configDir string) error) (*Server, error) {
	if configDir == "" {
		return nil, errors.New("config dir is empty")
	}

	s := &Server{dir: configDir}

	s.scheduler = profilescheduler.New(configDir, logf, func() error { return apply(configDir) })
	s.scheduler.Start()

	host := &tunnelHost{
		dir:   configDir,
		apply: apply,
		profiles: ProfileHooks{
			Dir:   func(*http.Request) string { return configDir },
			Apply: apply,
		},
	}
	handle := func(w http.ResponseWriter, r *http.Request) {
		ServeHTTP(w, r, Route(host, logf), logf)
	}

	path := SocketPath(configDir)
	listener, err := listenSocket(configDir)
	if err != nil {
		s.scheduler.Stop()
		return nil, err
	}
	s.listener = listener
	s.server = &http.Server{Handler: http.HandlerFunc(handle)}

	go func() {
		if err := s.server.Serve(listener); err != nil && !errors.Is(err, http.ErrServerClosed) {
			logf("profile API stopped: %v", err)
		}
	}()
	logf("profile API listening on %s", path)
	return s, nil
}

// Dir reports the configuration directory being served.
func (s *Server) Dir() string { return s.dir }

// Close stops the timer and the API, letting net.UnixListener unlink the socket.
func (s *Server) Close() {
	if s == nil {
		return
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.scheduler != nil {
		s.scheduler.Stop()
		s.scheduler = nil
	}
	if s.server != nil {
		_ = s.server.Close()
		s.server = nil
	}
	if s.listener != nil {
		_ = s.listener.Close()
		s.listener = nil
	}
	s.dir = ""
}

// tunnelHost answers the control API from inside a tunnel process.
//
// The OS owns the tunnel and the host code starts the core, so the routes that
// would start, stop or rebuild one are not available here: the app drives that
// through its own platform session (NEPacketTunnelProvider on iOS,
// VpnService on Android). Everything that only rewrites config.yaml — the
// profile routes and /clash/reload — works as on the desktop.
type tunnelHost struct {
	dir      string
	apply    func(configDir string) error
	profiles ProfileHooks
}

func (h *tunnelHost) Version() string { return "" }

func (h *tunnelHost) Runtime() map[string]string {
	dir := ""
	if executable, err := os.Executable(); err == nil {
		dir = executable
	}
	return map[string]string{"dir": dir}
}

func (h *tunnelHost) Path() (string, error) { return os.Executable() }

func (h *tunnelHost) Env() map[string]string {
	env := make(map[string]string)
	for _, entry := range os.Environ() {
		if key, value, found := strings.Cut(entry, "="); found {
			env[key] = value
		}
	}
	return env
}

func (h *tunnelHost) Memory() any { return nil }

// Status: a tunnel process only serves this API while its core runs and its
// tunnel is up, so both answers are true by definition.
func (h *tunnelHost) Status() (bool, bool) { return true, true }

func (h *tunnelHost) CoreStarted() bool { return true }

func (h *tunnelHost) Start(any, bool) *Response {
	return Error("the tunnel is started by the app, not by this API")
}

func (h *tunnelHost) StartCore(any) *Response {
	return Error("the tunnel is started by the app, not by this API")
}

func (h *tunnelHost) StopVPN() *Response {
	return Error("the tunnel is stopped by the app, not by this API")
}

// Reload re-reads config.yaml into the running core, the same hot apply a
// subscription refresh uses.
func (h *tunnelHost) Reload() *Response {
	if err := h.apply(h.dir); err != nil {
		return Error(err.Error())
	}
	return OK(nil)
}

func (h *tunnelHost) Stop() *Response {
	return Error("the tunnel is stopped by the app, not by this API")
}

func (h *tunnelHost) StopCore() *Response {
	return Error("the tunnel is stopped by the app, not by this API")
}

func (h *tunnelHost) Profiles() ProfileHooks { return h.profiles }
