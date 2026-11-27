package clashservice

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/listener"
	LC "github.com/metacubex/mihomo/listener/config"
	"github.com/metacubex/mihomo/tunnel"
)

// freePort 拿一个当前空闲的本地端口，避免测试固定端口撞上别的东西。
func freePort(t *testing.T) int {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("reserve port: %v", err)
	}
	port := listener.Addr().(*net.TCPAddr).Port
	if err := listener.Close(); err != nil {
		t.Fatalf("release port: %v", err)
	}
	return port
}

// shortTempDir 建一个短路径的临时目录：控制器 unix socket 路径有 104 字节上限，
// t.TempDir() 在 macOS 上经常超长，会导致控制器根本监听不起来。
func shortTempDir(t *testing.T) string {
	t.Helper()
	dir, err := os.MkdirTemp("/tmp", "clashyTest")
	if err != nil {
		t.Fatalf("create temp dir: %v", err)
	}
	t.Cleanup(func() { _ = os.RemoveAll(dir) })
	return dir
}

func proxyDialable(port int) error {
	conn, err := net.DialTimeout("tcp", fmt.Sprintf("127.0.0.1:%d", port), 300*time.Millisecond)
	if err != nil {
		return err
	}
	return conn.Close()
}

// TestStopEngineClosesInbound 覆盖「stop() 之后代理端口仍在监听」：mihomo 的
// executor.Shutdown 只关 TUN（listener.Cleanup 只 close tun listener），它的 CLI
// 靠进程退出收掉 inbound；桌面服务是常驻进程，必须自己关。
func TestStopEngineClosesInbound(t *testing.T) {
	dir := shortTempDir(t)
	port := freePort(t)
	config := fmt.Sprintf(`mixed-port: %d
mode: rule
log-level: warning
external-controller-unix: %s
dns:
  enable: false
proxies: []
rules:
  - MATCH,DIRECT
`, port, filepath.Join(dir, "api.sock"))
	if err := os.WriteFile(filepath.Join(dir, configFileName), []byte(config), 0o644); err != nil {
		t.Fatalf("write config: %v", err)
	}

	start := func(stage string) {
		t.Helper()
		if err := startEngine(dir, false); err != nil {
			t.Fatalf("%s: %v", stage, err)
		}
		if err := proxyDialable(port); err != nil {
			t.Fatalf("%s 之后 %d 端口没有监听: %v", stage, port, err)
		}
	}
	stop := func(stage string) {
		t.Helper()
		if err := stopEngine(); err != nil {
			t.Fatalf("%s: %v", stage, err)
		}
		if err := proxyDialable(port); err == nil {
			t.Fatalf("%s 之后 %d 端口仍在监听", stage, port)
		}
	}

	// 起 → 停，再起 → 停：第二遍同时验证关掉的监听还能正常重建。
	start("start")
	stop("stop")
	start("restart")
	stop("stop")
}

// TestCloseInboundListenersStopsPorts 覆盖移动端路径：libclash 的 C API stop()
// 走的是 executor.Shutdown + listener.Cleanup + CloseInboundListeners，和桌面端
// 共用同一份关闭逻辑，这里直接按那个顺序跑一遍。
func TestCloseInboundListenersStopsPorts(t *testing.T) {
	dir := shortTempDir(t)
	port := freePort(t)
	config := fmt.Sprintf(`mixed-port: %d
mode: rule
log-level: warning
external-controller-unix: %s
dns:
  enable: false
proxies: []
rules:
  - MATCH,DIRECT
`, port, filepath.Join(dir, "api.sock"))
	if err := os.WriteFile(filepath.Join(dir, configFileName), []byte(config), 0o644); err != nil {
		t.Fatalf("write config: %v", err)
	}
	if err := startEngine(dir, false); err != nil {
		t.Fatalf("start: %v", err)
	}
	if err := proxyDialable(port); err != nil {
		t.Fatalf("start 之后 %d 端口没有监听: %v", port, err)
	}
	apiAnswers(t, filepath.Join(dir, "api.sock"))

	// 移动端 stopTun()（关闭代理）的顺序：撤 TUN + 挂起 + 关入站监听，
	// 内核并不 Shutdown，控制器 API 必须还能应答。
	listener.ReCreateTun(LC.Tun{}, tunnel.Tunnel)
	tunnel.OnSuspend()
	CloseInboundListeners()

	if err := proxyDialable(port); err == nil {
		t.Fatalf("移动端 stopTun 之后 %d 端口仍在监听", port)
	}
	apiAnswers(t, filepath.Join(dir, "api.sock"))

	// 移动端 stop()（彻底结束内核）的完整序列。
	executor.Shutdown()
	listener.Cleanup()
	CloseInboundListeners()

	if err := proxyDialable(port); err == nil {
		t.Fatalf("移动端 stop 之后 %d 端口仍在监听", port)
	}
	_ = stopEngine()
}

// apiAnswers 通过控制器 unix socket 访问 /configs，确认内核的 API 还活着。
func apiAnswers(t *testing.T, socketPath string) {
	t.Helper()
	client := &http.Client{
		Transport: &http.Transport{
			DialContext: func(ctx context.Context, network string, addr string) (net.Conn, error) {
				var dialer net.Dialer
				return dialer.DialContext(ctx, "unix", socketPath)
			},
		},
		Timeout: 2 * time.Second,
	}
	resp, err := client.Get("http://unix/configs")
	if err != nil {
		t.Fatalf("控制器 API 不可用: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("控制器 API 返回 %d", resp.StatusCode)
	}
}

// TestDisableProxyKeepsCoreAlive 覆盖新语义：关闭代理（stop）只撤 TUN 和入站监听，
// 内核与控制器保持存活，/proxies 等 API 仍可用；再次开启代理时端口能重新监听。
func TestDisableProxyKeepsCoreAlive(t *testing.T) {
	dir := shortTempDir(t)
	port := freePort(t)
	socketPath := filepath.Join(dir, "api.sock")
	config := fmt.Sprintf(`mixed-port: %d
mode: rule
log-level: warning
external-controller-unix: %s
dns:
  enable: false
proxies: []
rules:
  - MATCH,DIRECT
`, port, socketPath)
	if err := os.WriteFile(filepath.Join(dir, configFileName), []byte(config), 0o644); err != nil {
		t.Fatalf("write config: %v", err)
	}
	t.Cleanup(func() { _ = core.shutdown() })

	if err := core.run(dir, false); err != nil {
		t.Fatalf("start: %v", err)
	}
	if err := proxyDialable(port); err != nil {
		t.Fatalf("start 之后 %d 端口没有监听: %v", port, err)
	}
	apiAnswers(t, socketPath)

	if err := core.disableProxy(); err != nil {
		t.Fatalf("disableProxy: %v", err)
	}
	if err := proxyDialable(port); err == nil {
		t.Fatalf("关闭代理之后 %d 端口仍在监听", port)
	}
	// core 没有跟着退出：控制器 API 依然应答，代理列表仍可读取。
	apiAnswers(t, socketPath)

	if running, vpn := core.status(); running || vpn {
		t.Fatalf("关闭代理后 status 应全为 false，实际 running=%v vpn=%v", running, vpn)
	}

	// 再次开启代理：走的是 runLocked 的重放配置分支。
	if err := core.run(dir, false); err != nil {
		t.Fatalf("restart: %v", err)
	}
	if err := proxyDialable(port); err != nil {
		t.Fatalf("重新开启代理后 %d 端口没有监听: %v", port, err)
	}
	apiAnswers(t, socketPath)
}

// TestStartCoreStopVpnStop 覆盖新的四段语义：
// startCore（内核起、端口不监听、API 可用）→ startVpn（端口开始监听）→
// stopVpn（端口关、API 还在）→ stop（内核与 API 一起结束）。
func TestStartCoreStopVpnStop(t *testing.T) {
	dir := shortTempDir(t)
	port := freePort(t)
	socketPath := filepath.Join(dir, "api.sock")
	config := fmt.Sprintf(`mixed-port: %d
mode: rule
log-level: warning
external-controller-unix: %s
dns:
  enable: false
proxies: []
rules:
  - MATCH,DIRECT
`, port, socketPath)
	if err := os.WriteFile(filepath.Join(dir, configFileName), []byte(config), 0o644); err != nil {
		t.Fatalf("write config: %v", err)
	}
	t.Cleanup(func() { _ = core.shutdown() })

	// commitAPIState 会写期望状态文件，测试里指到临时目录，免得碰 /Library。
	core.statePath = filepath.Join(dir, "state.json")
	t.Cleanup(func() { core.statePath = "" })
	profile := map[string]any{"configDir": dir}

	// startCore：API 可用，端口不监听
	if res := startCoreProfile(profile); res.Code != 0 {
		t.Fatalf("startCore: %s", res.Msg)
	}
	apiAnswers(t, socketPath)
	if err := proxyDialable(port); err == nil {
		t.Fatalf("startCore 之后 %d 端口不应监听", port)
	}
	// 新加的 GET /clash/core/status 语义：内核在跑、代理没开。
	if !core.isStarted() {
		t.Fatalf("startCore 之后 core.isStarted() 应为 true")
	}

	// startVpn：端口开始监听。托盘这类没有 profile 的调用方会传空 body，
	// 服务端必须沿用持久化的那份 —— 这里就用空 map 验证这条路。
	if res := startProfile(map[string]any{}, false); res.Code != 0 {
		t.Fatalf("startVpn(空 body): %s", res.Msg)
	}
	if err := proxyDialable(port); err != nil {
		t.Fatalf("startVpn 之后 %d 端口没有监听: %v", port, err)
	}

	// stopVpn：端口关，API 还在
	if res := stopVpn(); res.Code != 0 {
		t.Fatalf("stopVpn: %s", res.Msg)
	}
	if err := proxyDialable(port); err == nil {
		t.Fatalf("stopVpn 之后 %d 端口仍在监听", port)
	}
	apiAnswers(t, socketPath)

	// stopClash（/clash/core/stop）：内核与控制器一起结束
	if res := stopClash(); res.Code != 0 {
		t.Fatalf("stop: %s", res.Msg)
	}
	if running, vpn := core.status(); running || vpn {
		t.Fatalf("stop 之后 status 应全为 false，实际 running=%v vpn=%v", running, vpn)
	}
	if core.isStarted() {
		t.Fatalf("stop 之后 core.isStarted() 应为 false")
	}

	// 托盘没有 profile：stop 之后再用空 body 点「启动」也要能重新起内核。
	if res := startProfile(map[string]any{}, false); res.Code != 0 {
		t.Fatalf("stop 之后 start(空 body): %s", res.Msg)
	}
	if err := proxyDialable(port); err != nil {
		t.Fatalf("stop 之后重新 start，%d 端口没有监听: %v", port, err)
	}
	_ = stopClash()
}

// TestStopRouteKeepsCoreAlive 锁定 /clash/stop 的新语义：它只关代理（撤 TUN、
// 关入站端口），内核与控制器继续跑，所以 /proxies 仍应答；真正停内核走
// /clash/core/stop。
func TestStopRouteKeepsCoreAlive(t *testing.T) {
	dir := shortTempDir(t)
	port := freePort(t)
	socketPath := filepath.Join(dir, "api.sock")
	config := fmt.Sprintf(`mixed-port: %d
mode: rule
log-level: warning
external-controller-unix: %s
dns:
  enable: false
proxies: []
rules:
  - MATCH,DIRECT
`, port, socketPath)
	if err := os.WriteFile(filepath.Join(dir, configFileName), []byte(config), 0o644); err != nil {
		t.Fatalf("write config: %v", err)
	}
	t.Cleanup(func() { _ = core.shutdown() })

	core.statePath = filepath.Join(dir, "state.json")
	t.Cleanup(func() { core.statePath = "" })
	profile := map[string]any{"configDir": dir}

	if res := startProfile(profile, false); res.Code != 0 {
		t.Fatalf("start: %s", res.Msg)
	}
	if err := proxyDialable(port); err != nil {
		t.Fatalf("start 之后 %d 端口没有监听: %v", port, err)
	}

	// /clash/stop：只关代理
	if res := (desktopHost{}).Stop(); res.Code != 0 {
		t.Fatalf("stop(关代理): %s", res.Msg)
	}
	if err := proxyDialable(port); err == nil {
		t.Fatalf("stop 之后 %d 端口仍在监听", port)
	}
	apiAnswers(t, socketPath)
	if !core.isStarted() {
		t.Fatalf("stop(关代理) 之后内核应继续运行")
	}
	if _, vpn := core.status(); vpn {
		t.Fatalf("stop(关代理) 之后 TUN 应为关闭")
	}

	// 代理关着也能再开回来
	if res := (desktopHost{}).StopVPN(); res.Code != 0 {
		t.Fatalf("stopVpn: %s", res.Msg)
	}
	if res := startProfile(map[string]any{}, false); res.Code != 0 {
		t.Fatalf("stop 之后再 start: %s", res.Msg)
	}
	if err := proxyDialable(port); err != nil {
		t.Fatalf("再 start 之后 %d 端口没有监听: %v", port, err)
	}

	// /clash/core/stop：停内核
	if res := (desktopHost{}).StopCore(); res.Code != 0 {
		t.Fatalf("stopCore: %s", res.Msg)
	}
	if core.isStarted() {
		t.Fatalf("stopCore 之后 core.isStarted() 应为 false")
	}
}
