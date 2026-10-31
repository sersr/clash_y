import 'dart:io';

import 'package:clash_service_android/clash_service_android.dart' as android;
import 'package:file/local.dart' as f;
import 'package:server/server.dart' show ClashProfile;

import 'src/service/clash_service_linux.dart';
import 'src/service/clash_service_macos_cmd.dart';
import 'src/service/clash_service_macos_tray.dart';
import 'src/service/clash_service_windows.dart';

export 'package:server/server.dart';

export 'src/service/clash_service_windows.dart';

const fs = f.LocalFileSystem();

abstract final class ClashService {
  /// 桌面端后台服务是否已安装。
  static Future<bool> isInstalled() async {
    if (Platform.isMacOS) return HelperInstaller.isInstalled();
    if (Platform.isLinux) return isSystemdServiceInstalled();
    if (Platform.isWindows) return isServiceInstalled();
    if (Platform.isAndroid) return true;
    return false;
  }

  /// Whether macOS has an active VPN connection or a route through a utun
  /// interface that could conflict with Clashy.
  static Future<bool> hasOtherVpnConnection({
    bool clashyIsRunning = false,
  }) async {
    if (!Platform.isMacOS) return false;
    return HelperInstaller.hasOtherVpnConnection(
      checkTunnelRoutes: !clashyIsRunning,
    );
  }

  /// Brings the VPN service up for [profile].
  ///
  /// Android 使用 VPN 后端；macOS 安装并启动 privileged helper，同时配置
  /// Tray；Linux 写入
  /// systemd unit 并启动（未提权时弹 pkexec 密码框）；Windows 安装并启动
  /// SCM 服务（未提权时弹 UAC 密码框）。
  ///
  /// [profile] carries the configuration directory plus the subscription the
  /// service keeps refreshing while the app is not running.
  ///
  /// [allowList] 为 `true` 时仅将 [allowedApplications]（以及 Android VPN
  /// 自身包名）纳入 VPN；为 `false` 时使用全局路由和
  /// [disallowedApplications] 排除列表。
  ///
  /// 返回 `false` 表示平台没有 VPN 后端，或后端拒绝启动 —— 例如用户拒绝了
  /// Android VPN 授权对话框、提权被取消、或 Windows 非管理员运行。
  static Future<bool> start(
    ClashProfile profile, {
    bool allowList = false,
    List<String> allowedApplications = const [],
    List<String> disallowedApplications = const [],
    String? trayClashSocket,
  }) async {
    if (Platform.isAndroid) {
      return android.AndroidVpnService.start(
        profile.configDir,
        profileUrl: profile.url,
        updateIntervalMinutes: profile.updateInterval,
        updateTime: profile.updateTime,
        allowList: allowList,
        allowedApplications: allowedApplications,
        disallowedApplications: disallowedApplications,
      );
    }

    if (Platform.isMacOS) {
      await HelperInstaller.install();
      final running = await HelperInstaller.isRunning();
      if (!running) return false;
      final clashSocket = trayClashSocket;
      if (clashSocket == null) {
        throw ArgumentError.value(
          trayClashSocket,
          'trayClashSocket',
          'is required on macOS',
        );
      }
      await TrayInstaller.configure(clashSocket: clashSocket);
      return true;
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

  /// Updates the profile a running service refreshes itself from.
  ///
  /// Desktop services are driven through their IPC API instead; this only
  /// covers Android, whose backend lives in the VPN process.
  static Future<bool> updateProfile(ClashProfile profile) async {
    if (Platform.isAndroid) {
      return android.AndroidVpnService.updateProfile(
        configDir: profile.configDir,
        profileUrl: profile.url,
        updateIntervalMinutes: profile.updateInterval,
        updateTime: profile.updateTime,
      );
    }
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

  static Future<bool> stop() async {
    if (Platform.isAndroid) {
      return android.AndroidVpnService.close();
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
