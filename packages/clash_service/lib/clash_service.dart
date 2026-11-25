import 'dart:io';

import 'package:clash_service_android/clash_service_android.dart' as android;
import 'package:file/local.dart' as f;
import 'package:nop/nop.dart';
import 'package:server/clash_service_windows.dart';
import 'package:server/server.dart' show ApiResp, ClashProfile, version;

import 'src/service/api.dart';
import 'src/service/clash_service_linux.dart';
import 'src/service/clash_service_ios.dart';
import 'src/service/clash_service_macos_cmd.dart';

export 'package:server/server.dart';

const fs = f.LocalFileSystem();

abstract final class ClashService {
  /// iOS control socket path shared with the Packet Tunnel extension.
  static Future<String> get iosControlSocketPath =>
      IOSVpnService.controlSocketPath;

  /// 桌面端后台服务是否已安装。
  static Future<bool> isInstalled() async {
    if (Platform.isMacOS) return MacOSServiceProcess.isInstalled();
    if (Platform.isLinux) return isSystemdServiceInstalled();
    if (Platform.isWindows) return isServiceInstalled();
    if (Platform.isAndroid) return true;
    if (Platform.isIOS) return IOSVpnService.isConfigured();
    return false;
  }

  /// Whether macOS has an active VPN connection or a route through a utun
  /// interface that could conflict with Clashy.
  static Future<bool> hasOtherVpnConnection({
    bool clashyIsRunning = false,
  }) async {
    if (!Platform.isMacOS) return false;
    return MacOSServiceProcess.hasOtherVpnConnection(
      checkTunnelRoutes: !clashyIsRunning,
    );
  }

  /// Reinstalls the desktop service if its running version is older than this app.
  static Future<void> updateDesktopServiceIfOutdated({
    required String controllerSocketPath,
  }) async {
    if (!Platform.isMacOS && !Platform.isLinux && !Platform.isWindows) return;
    if (!await _isDesktopServiceRunning()) return;

    final serviceVersion = await ClashServiceApi.getServiceVersion();
    if (serviceVersion != null && !_isVersionOlder(serviceVersion, version)) {
      return;
    }

    if (serviceVersion == null) {
      Log.e('Could not read clashyService version; reinstalling the service.');
    } else {
      Log.e(
        'clashyService $serviceVersion is older than $version; '
        'reinstalling the service.',
      );
    }

    await _reinstallDesktopService(controllerSocketPath);
  }

  static Future<bool> _isDesktopServiceRunning() async {
    if (Platform.isMacOS) return MacOSServiceProcess.isRunning();
    if (Platform.isLinux) return isSystemdServiceRunning();
    if (Platform.isWindows) return isServiceRunning();
    return false;
  }

  static Future<void> _reinstallDesktopService(
    String controllerSocketPath,
  ) async {
    if (Platform.isMacOS) {
      await MacOSServiceProcess.install(
        clashSocketPath: controllerSocketPath,
        forceRestart: true,
      );
      return;
    }

    if (Platform.isLinux) {
      final exitCode = await installSystemdService(forceRestart: true);
      if (exitCode != 0) {
        throw StateError(
          'Failed to reinstall the Linux clashyService (exit code $exitCode).',
        );
      }
      return;
    }

    if (Platform.isWindows) {
      if (!await stopService()) {
        throw StateError('Failed to stop the outdated Windows clashyService.');
      }
      if (!await startService()) {
        throw StateError('Failed to reinstall the Windows clashyService.');
      }
    }
  }

  static bool _isVersionOlder(String installed, String required) {
    final installedParts = _versionParts(installed);
    final requiredParts = _versionParts(required);
    if (installedParts == null) return true;
    if (requiredParts == null) {
      throw FormatException('Invalid bundled clashyService version: $required');
    }

    for (
      var index = 0;
      index < installedParts.length || index < requiredParts.length;
      index++
    ) {
      final installedPart = index < installedParts.length
          ? installedParts[index]
          : 0;
      final requiredPart = index < requiredParts.length
          ? requiredParts[index]
          : 0;
      if (installedPart != requiredPart) {
        return installedPart < requiredPart;
      }
    }
    return false;
  }

  static List<int>? _versionParts(String value) {
    final parts = value.split('.');
    final result = <int>[];
    for (final part in parts) {
      final number = int.tryParse(part);
      if (number == null || number < 0) return null;
      result.add(number);
    }
    return result;
  }

  /// Starts the Clash core and enables the VPN for [profile].
  ///
  /// Desktop platforms ensure their service is running, start the core, then
  /// enable and verify the VPN.
  ///
  /// [profile] carries the configuration directory, subscription, and optional
  /// script the service uses while the app is not running.
  ///
  /// [allowList] 为 `true` 时仅将 [allowedApplications]（以及 Android VPN
  /// 自身包名）纳入 VPN；为 `false` 时使用全局路由和
  /// [disallowedApplications] 排除列表。
  ///
  /// Returns `false` if the platform has no VPN backend or startup fails.
  static Future<bool> start(
    ClashProfile profile, {
    bool allowList = false,
    List<String> allowedApplications = const [],
    List<String> disallowedApplications = const [],
    required String controllerSocketPath,
  }) async {
    if (Platform.isAndroid) {
      return android.AndroidVpnService.start(
        profile.configDir,
        profileUrl: profile.url,
        profileName: profile.name,
        script: profile.script,
        controllerSocketPath: controllerSocketPath,
        updateIntervalMinutes: profile.updateInterval,
        updateTime: profile.updateTime,
        allowList: allowList,
        allowedApplications: allowedApplications,
        disallowedApplications: disallowedApplications,
      );
    }

    if (Platform.isIOS) {
      return IOSVpnService.start(profile);
    }

    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      if (!await _startDesktopService(
        controllerSocketPath: controllerSocketPath,
      )) {
        return false;
      }
      if (!await ClashServiceApi.isClashRunning()) {
        final coreResponse = await ClashServiceApi.startClashCore(profile);
        if (!coreResponse.success) return false;
      }
      final vpnResponse = await ClashServiceApi.startVpn(profile);
      return vpnResponse.success && await ClashServiceApi.isVpnActive();
    }

    return false;
  }

  static Future<bool> _startDesktopService({
    required String controllerSocketPath,
  }) async {
    if (Platform.isMacOS) {
      await MacOSServiceProcess.install(clashSocketPath: controllerSocketPath);
      return MacOSServiceProcess.isRunning();
    }

    if (Platform.isLinux) {
      if (await installSystemdService() != 0) return false;
      return isSystemdServiceRunning();
    }

    if (Platform.isWindows) {
      // A developer may run clashyservice directly from an elevated terminal
      // while testing. Reuse that API server instead of asking SCM to launch a
      // second instance that collides on the same named pipe.
      if (await ClashServiceApi.getServiceVersion() != null) return true;
      if (!await startService()) return false;
      // 服务已经在 RUNNING，但命名管道可能还没开始监听；先短轮询到管道可用，
      // 免得紧接着的 status 请求走进 2 秒一次的重试退避。
      return _waitUntilWindowsServiceReady();
    }
    return false;
  }

  /// 等待 Windows 服务的控制管道可用，最多 2 秒。
  static Future<bool> _waitUntilWindowsServiceReady() async {
    for (var i = 0; i < 20; i++) {
      if (await ClashServiceApi.getServiceVersion() != null) return true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return true;
  }

  static Future<ApiResp> getClashEnv() => ClashServiceApi.getClashEnv();

  static Future<ApiResp> startClash(ClashProfile profile) =>
      ClashServiceApi.startClash(profile);

  static Future<ApiResp> startVpn(ClashProfile profile) =>
      ClashServiceApi.startVpn(profile);

  static Future<ApiResp> stopVpn() => ClashServiceApi.stopVpn();

  static Future<ApiResp> reloadClashConfig() =>
      ClashServiceApi.reloadClashConfig();

  static Future<ApiResp> updateClashProfile(ClashProfile profile) =>
      ClashServiceApi.updateClashProfile(profile);

  static Future<ApiResp> stopClash() => ClashServiceApi.stopClash();

  static Future<bool> isClashRunning() => ClashServiceApi.isClashRunning();

  /// Whether the platform's VPN interface or tunnel is active.
  static Future<bool> isVpnActive() async {
    if (Platform.isAndroid) return android.AndroidVpnService.isVpnActive();
    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      return ClashServiceApi.isVpnActive();
    }
    return false;
  }

  /// Starts the mihomo core without enabling its VPN interface.
  ///
  /// The controller API remains available so the application can load proxies
  /// before the user turns the VPN on.
  static Future<bool> startCore(
    ClashProfile profile, {
    required String controllerSocketPath,
  }) async {
    if (Platform.isAndroid) {
      return android.AndroidVpnService.startCore(
        profile.configDir,
        profileUrl: profile.url,
        profileName: profile.name,
        script: profile.script,
        controllerSocketPath: controllerSocketPath,
        updateIntervalMinutes: profile.updateInterval,
        updateTime: profile.updateTime,
      );
    }

    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      if (!await _startDesktopService(
        controllerSocketPath: controllerSocketPath,
      )) {
        return false;
      }
      if (await ClashServiceApi.isClashRunning()) return true;

      final response = await ClashServiceApi.startClashCore(profile);
      if (!response.success) {
        final details = response.data ?? response.msg;
        throw StateError(
          details == null || '$details'.isEmpty
              ? 'Desktop service failed to start the Clash core.'
              : 'Desktop service failed to start the Clash core: $details',
        );
      }
      return true;
    }

    return false;
  }

  /// Reloads the Android core configuration without changing VPN state.
  static Future<bool> reloadCoreConfig(
    ClashProfile profile, {
    String? controllerSocketPath,
  }) async {
    if (!Platform.isAndroid) return false;
    return android.AndroidVpnService.reloadConfig(
      profile.configDir,
      profileUrl: profile.url,
      profileName: profile.name,
      script: profile.script,
      controllerSocketPath: controllerSocketPath,
      updateIntervalMinutes: profile.updateInterval,
      updateTime: profile.updateTime,
    );
  }

  /// Whether the Android VPN interface is currently established.
  /// Updates the profile shown/used by a running service without restarting
  /// the core.
  ///
  /// Desktop services are driven through their IPC API instead; this only
  /// covers Android, whose backend lives in the VPN process.
  static Future<bool> updateProfile(
    ClashProfile profile, {
    String? controllerSocketPath,
  }) async {
    if (Platform.isAndroid) {
      return android.AndroidVpnService.updateProfile(
        configDir: profile.configDir,
        profileUrl: profile.url,
        profileName: profile.name,
        script: profile.script,
        controllerSocketPath: controllerSocketPath,
        updateIntervalMinutes: profile.updateInterval,
        updateTime: profile.updateTime,
      );
    }
    if (Platform.isIOS) {
      return IOSVpnService.updateProfile(profile);
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
    if (Platform.isIOS) {
      return IOSVpnService.close();
    }

    if (Platform.isMacOS) {
      if (!await MacOSServiceProcess.isRunning()) return true;

      await MacOSServiceProcess.stop();
      return !await MacOSServiceProcess.isRunning();
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
      return android.AndroidVpnService.stopVpn();
    }
    if (Platform.isIOS) {
      return IOSVpnService.close();
    }

    if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      try {
        final response = await ClashService.stopVpn();
        if (!response.success) {
          return false;
        }
        return true;
      } catch (e) {
        return false;
      }
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
    if (Platform.isIOS) {
      return IOSVpnService.uninstall();
    }

    if (Platform.isMacOS) {
      await MacOSServiceProcess.uninstall();
      return !await MacOSServiceProcess.isRunning();
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
