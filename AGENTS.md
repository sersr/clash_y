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
- 优先复用已有实现；只有在确实减少重复且不会引入不必要抽象或复杂度时，才提取共享实现。
- macOS 特权 TUN helper 的安装路径、LaunchDaemon 配置和注册/安装实现只能维护一份；调用方复用已有定义或接口，不得复制 `/Library/PrivilegedHelperTools/` 等特权路径、plist 内容或安装脚本。

## 桌面常驻服务与原生二进制

- 桌面常驻服务端是 Go 实现，源码在 `packages/clash_core/core/cmd/`；`go build ./cmd` 产出 `clashyService`（Windows 为 `clashyservice.exe`），其 `serviceVersion` 必须与 `packages/server/lib/server.dart` 的 `version` 保持一致。
- `packages/server` 只保留 Flutter 端与服务端共用的 `ApiResp`、`ClashProfile`、IPC 端点常量，以及 Windows SCM 服务/TUN helper 的安装、启停、卸载；不要在其中新增服务端运行逻辑。
- 三平台随包原生二进制（服务端、TUN helper、macOS 托盘）由 `packages/clash_service/hook/` 构建，产物先落到 `packages/clash_service/build/bin`，再以 `bin/*` DataAsset 交付。
- 这两个 Go 二进制默认 `CGO_ENABLED=0`（依赖图里没有 cgo 包，Windows 上无需 gcc）。确实需要 cgo 时设 `CLASHY_GO_CGO=1` 或 `hooks.user_defines` 的 `clash_service: {cgo: true}`；hook 会自动定位 MSYS2 的 mingw-w64 gcc（`mingw64`/`ucrt64`/`clang64`），也可用 `CLASHY_CC` 指定 `gcc.exe`。
- 这两个 Go 二进制必须带 `-tags with_gvisor` 构建（hook 里的 `goBuildTags`）；桌面 tun 默认走 gvisor 栈，缺标签启动 TUN 会报 `gVisor is not included in this build`，手工 `go build` 验证时也要带。
- 特权 TUN helper 的安装实现每个平台只维护一份：macOS/Linux 由 Go 服务端负责，Windows 由应用提权脚本注册（服务名与 Go 服务端共用 `clashy_tun_helper`）。

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
