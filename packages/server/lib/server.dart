import 'dart:io';

export 'src/server/models/models.dart';
export 'src/server/response.dart';

/// 桌面服务版本号，必须与 Go 服务端的 `serviceVersion`
/// (`packages/clash_core/core/internal/clashsvc/clashService.go`) 保持一致。
///
/// `ClashService.updateDesktopServiceIfOutdated` 用它判断是否需要重装服务。
const version = '0.0.1';

/// 桌面服务控制 API 的 IPC 端点，与 Go 服务端的监听地址一致。
String get clashSocket {
  if (!Platform.isWindows) {
    return '/tmp/clashy/clash_service.sock';
  }

  return r'\\.\pipe\clashy\clash_service.pipe';
}
