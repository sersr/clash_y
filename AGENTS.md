# 项目约定

## 项目结构

- Flutter 功能页面按功能放在 `lib/pages/<功能名>/`；页面入口文件放在该目录根部。
- 页面对应的状态控制器放在 `controller/`，可复用的局部组件放在 `widget/`。参考 `lib/pages/home/` 和 `lib/pages/application_list/`。
- 页面控制器遵循 Home 的生命周期与依赖注入方式：使用 `NopLifecycle`，在 `initController()` 中通过 `router.put(() => Controller())` 注册，并在页面或控制器中用 `getType()` / `context.getType()` 获取；不要在页面中手动创建和销毁控制器。
- 跨页面的事件接口放在 `lib/event/base/`，具体实现放在 `lib/event/impl/`；通过 `Repository` 组合并提供给页面和控制器使用。
- 页面路由统一在 `lib/_route/routes.dart` 声明，通过 `RouterPage` 注册子页面并生成路由；页面跳转使用生成的 `NavRoutes.<name>().go()`，不要直接用 `Navigator.push`。
- `*.g.dart` 是生成文件。修改对应源文件和注解后再生成，不直接编辑生成文件。
- 多功能共享的基础类型、存储和通用组件放在 `packages/common/`，避免把通用实现复制到单个页面目录。
- 编写页面样式前先检查 `packages/common/` 是否已有对应组件；优先复用 `common` 提供的按钮、弹窗、系统栏等样式，不直接另造一套。若共享样式确实缺失，再扩展 `common` 并从 `common.dart` 导出。

## 复用与常量

- 相同语义的常量只定义一处；其他位置引用同一个变量，不重复硬编码或声明副本。
- `packages/js_interpreter` 是上游 `js_interpreter` 0.0.5 的补丁副本（只修了解析器在对象展开 `{...x}` 上的 super/await 扫描），通过根 `pubspec.yaml` 的 `dependency_overrides` 生效；上游修好后删掉这个覆盖和副本。
- 优先复用已有实现；只有在确实减少重复且不会引入不必要抽象或复杂度时，才提取共享实现。
- macOS 服务的安装路径、plist 内容和注册脚本只在 `packages/clash_service/lib/src/service/clash_service_macos_cmd.dart` 维护一份；调用方复用已导出的接口，不得复制 `/Library/Application Support/Clashy/bin/`、`/Library/LaunchDaemons`、`~/Library/LaunchAgents` 路径或 plist 文本。
- macOS 的服务副本不要放进 `/Library/PrivilegedHelperTools`：该目录由 AppleSystemPolicy 评估，开发构建的 ad-hoc 签名会被直接拒绝执行，launchd 无限重启、应用误判为未安装而每次开机都提权。root 拥有的普通系统目录已经满足「用户不可替换」的要求。

## 桌面常驻服务与原生二进制

- 桌面常驻服务端是 Go 实现，源码在 `packages/clash_core/core/cmd/`；`go build ./cmd` 产出 `clashyService`（Windows 为 `clashyservice.exe`），其 `serviceVersion` 必须与 `packages/server/lib/server.dart` 的 `version` 保持一致。
- 服务端在每个平台都以特权身份运行并自己创建/配置 TUN：Windows 是 `LocalSystem` 服务（自己建 Wintun、写路由），macOS 是 `/Library/LaunchDaemons` 的 root LaunchDaemon，Linux 是 systemd system unit（root）。不要再引入独立的 tun-helper 进程或 IPC 代理。
- macOS 托盘是用户 GUI 会话里的 LaunchAgent，装在当前用户的 `~/Library/LaunchAgents`（不需要 root，app 换位置只重写这份用户 plist）；system 域的守护进程没有 WindowServer 连接，不能由它拉起或自己画菜单栏。
- 服务端自己写的状态/日志放在机器级目录（macOS `/Library/Application Support/Clashy`、Windows `%ProgramData%\Clashy`、Linux `/var/lib/clashy`），不要落在用户可写的 profile 目录里。
- 特权守护进程的控制面只放行安装它的那个桌面用户：安装器把 uid/SID 以 `--allowed-uid` / `--allowed-sid` 传给服务（macOS plist、Linux unit、Windows `sc binPath`），服务在 accept 时用 peer credentials 校验 uid、或用该 SID 生成管道 DACL；root/SYSTEM/Administrators 始终放行。不要退回到 `0666` socket 或 `BU` 的管道描述符。
- 特权服务不以 root 身份跟随用户可写目录里的符号链接：配置入口会拒绝符号链接和非普通文件的 `config.yaml`，新增读文件的路径时沿用同样的检查。
- `packages/server` 只保留 Flutter 端与服务端共用的 `ApiResp`、`ClashProfile`、IPC 端点常量，以及 Windows SCM 服务/TUN 的安装、启停、卸载；不要在其中新增服务端运行逻辑。
- 三平台随包原生二进制（服务端、macOS 托盘）由 `packages/clash_service/hook/` 构建，产物先落到 `packages/clash_service/build/bin`，再以 `bin/*` DataAsset 交付。
- 这两个 Go 二进制默认 `CGO_ENABLED=0`（依赖图里没有 cgo 包，Windows 上无需 gcc）。确实需要 cgo 时设 `CLASHY_GO_CGO=1` 或 `hooks.user_defines` 的 `clash_service: {cgo: true}`；hook 会自动定位 MSYS2 的 mingw-w64 gcc（`mingw64`/`ucrt64`/`clang64`），也可用 `CLASHY_CC` 指定 `gcc.exe`。
- 这两个 Go 二进制必须带 `-tags with_gvisor` 构建（hook 里的 `goBuildTags`）；桌面 tun 默认走 gvisor 栈，缺标签启动 TUN 会报 `gVisor is not included in this build`，手工 `go build` 验证时也要带。hook 统一用 `-ldflags '-s -w'` 剥离调试符号（体积小约 30%，panic 栈仍可读）。
- 订阅刷新（下载、profile 脚本、app 自有 key 覆盖、写回 `config.yaml` 并保留 `.bak`）只有一份实现：`core/internal/profilerefresh`，入口 `RefreshFile`。桌面守护进程、Android VPN 服务、iOS Packet Tunnel 都调它，不要再在 Kotlin/Swift 里重写下载或 YAML/JS 处理。脚本（JavaScript）用纯 Go 的 `goja`，不引入 cgo：脚本拿到全局 `profileConfig`，需定义 `main(config)` 并返回配置对象；返回 JSON 字符串或其他类型一律按失败处理（Dart 端写首份配置时保持同一契约）。超时 5s、失败则保留原配置；脚本先跑，随后再用当前文件覆盖 app 自己管理的 key（`mixed-port`/`mode`/`tun`/`dns` 等）。
- 配置引用的 GeoIP/GeoSite 数据由 `core/internal/geoensure` 预下载（多镜像、原子写入、体积校验），入口是 Go 的 `prepare`/`startTun`；Android 必须在 `establishTun()` **之前**调用 `ClashCore.prepare(configDir)`。TUN 一旦建立，默认路由就归隧道，core 自己的 DNS/下载会进黑洞，表现为 `lookup ...: no such host` 然后整个解析失败、VPN 建好又被拆掉。

## Flutter 响应式状态

- 页面和控制器状态遵循项目现有的响应式写法：用 `.al` 创建可观察值，并在界面中用 `Cs` 读取和更新状态。
- 这类状态不要改用 `ChangeNotifier` / `AnimatedBuilder`，除非该状态明确需要 Flutter 原生监听模式。

## 应用包名名单

- 新增或修改包名时保持列表无重复项；保存时沿用列表格式。

## Git 提交

- 创建 Git 提交时，提交信息中不要添加作者或共同作者署名（包括 `Co-authored-by` trailer），也不要通过 `--author` 指定作者。

## Flutter Apple 平台依赖

- Flutter iOS/macOS 工程优先使用 Swift Package Manager（SPM）集成原生依赖；Flutter 3.44 起默认启用 SPM。不要为应用新增 CocoaPods/Podfile 集成。
- 项目内 Flutter 插件应提供平台对应的 `Package.swift`，并将源文件放在 SwiftPM package 的 `Sources/<target>/` 下；若插件还需兼容未迁移的 Flutter 工程，同时保留并维护 Podspec。
- 修改原生依赖后运行 `flutter pub get`，并验证对应 Apple 平台构建；不要依赖 `pod install`。
