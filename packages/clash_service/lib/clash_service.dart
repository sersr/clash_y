import 'dart:io';

import 'package:clash_service_android/clash_service_android.dart' as android;
import 'package:file/local.dart' as f;

import 'src/service/clash_service_linux.dart';
import 'src/service/clash_service_macos_cmd.dart';
import 'src/service/clash_service_windows.dart';

export 'package:server/server.dart';

export 'src/service/clash_service_windows.dart';

const fs = f.LocalFileSystem();

abstract final class ClashService {
  /// Brings the VPN service up for the configuration in [configDir].
  ///
  /// Android 使用 VPN 后端；macOS 安装并启动 privileged helper；Linux 写入
  /// systemd unit 并启动（未提权时弹 pkexec 密码框）；Windows 安装并启动
  /// SCM 服务（未提权时弹 UAC 密码框）。
  ///
  /// 返回 `false` 表示平台没有 VPN 后端，或后端拒绝启动 —— 例如用户拒绝了
  /// Android VPN 授权对话框、提权被取消、或 Windows 非管理员运行。
  static Future<bool> start(
    String configDir, {
    List<String> allowedApplications = const [],
    List<String> disallowedApplications = const [],
  }) async {
    if (Platform.isAndroid) {
      return android.AndroidVpnService.start(
        configDir,
        allowedApplications: allowedApplications,
        disallowedApplications: disallowedApplications,
      );
    }

    if (Platform.isMacOS) {
      if (await HelperInstaller.isRunning()) return true;

      await HelperInstaller.install();
      return HelperInstaller.isRunning();
    }

    if (Platform.isLinux) {
      if (await installSystemdService() != 0) return false;
      return isSystemdServiceRunning();
    }

    if (Platform.isWindows) {
      return startService();
    }

    // iOS has no VPN backend wired up here.
    return false;
  }

  /// Tears the VPN service down.
  ///
  /// Linux 停止 systemd 服务但保留安装；Windows 停止 SCM 服务（未提权时
  /// 弹 UAC）。已停止时直接返回 `true`，不触发提权。
  static Future<bool> close() async {
    if (Platform.isAndroid) {
      return android.AndroidVpnService.close();
    }

    if (Platform.isMacOS) {
      if (!await HelperInstaller.isRunning()) return true;

      await HelperInstaller.stop();
      return !await HelperInstaller.isRunning();
    }

    if (Platform.isLinux) {
      if (!await isSystemdServiceRunning()) return true;
      await stopSystemdService();
      return !await isSystemdServiceRunning();
    }

    if (Platform.isWindows) {
      return stopService();
    }

    return false;
  }

  /// Removes the VPN service entirely.
  ///
  /// Linux 删除 systemd unit；Windows 卸载 SCM 服务（未提权时弹 UAC）。
  static Future<bool> uninstall() async {
    if (Platform.isAndroid) {
      return android.AndroidVpnService.close();
    }

    if (Platform.isMacOS) {
      if (!await HelperInstaller.isInstalled()) return true;

      await HelperInstaller.uninstall();
      return !await HelperInstaller.isInstalled();
    }

    if (Platform.isLinux) {
      if (!await File(systemdUnitPath).exists()) return true;
      await uninstallSystemdService();
      return !await File(systemdUnitPath).exists();
    }

    if (Platform.isWindows) {
      return uninstallService();
    }

    return false;
  }
}
