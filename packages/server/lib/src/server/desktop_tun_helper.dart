import 'dart:io';

import 'linux_tun_helper.dart';
import 'macos_tun_helper.dart';
import 'windows_tun_helper.dart';

/// 三个桌面平台统一的 TUN helper 入口。
///
/// POSIX 平台的 helper 会创建 TUN 接口并通过 SCM_RIGHTS 把 fd 交给核心；
/// Windows 的 helper 只负责创建并配置 Wintun 网卡，核心随后打开同一网卡。
abstract final class DesktopTunHelper {
  static Future<void> ensureRegistered() async {
    if (Platform.isMacOS) return MacOSTunHelper.ensureRegistered();
    if (Platform.isLinux) return LinuxTunHelper.ensureRegistered();
    if (Platform.isWindows) return WindowsTunHelper.ensureRegistered();
    throw UnsupportedError('TUN helper is unavailable on ${Platform.operatingSystem}');
  }
}
