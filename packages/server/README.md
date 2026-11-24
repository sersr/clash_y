# server

Clashy 桌面服务与 Flutter 端共用的最小支持库。桌面服务端本身由 Go 实现，源码在
`packages/clash_core/core/cmd/`。

- `lib/server.dart`：`ApiResp`、`ClashProfile` 的导出，服务版本 `version` 与 IPC
  端点 `clashSocket`。
- `lib/tray_asset.dart`：随包原生二进制的文件名、DataAsset 包路径与输出目录约定。
- `lib/clash_service_windows.dart`：Windows SCM 服务与特权 TUN helper 的安装、启停
  和卸载（未提权时经 UAC 提权）。
