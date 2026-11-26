import 'dart:io';

import 'package:clash_service_android/clash_service_android.dart' as android;
import 'package:file/local.dart' as f;
import 'package:nop/nop.dart';
import 'package:server/clash_service_windows.dart';
import 'package:path/path.dart' as p;
import 'package:server/server.dart' show ApiResp, ClashProfile, version;

import 'src/service/api.dart';
import 'src/service/clash_service_ios.dart';
import 'src/service/clash_service_linux.dart';
import 'src/service/clash_service_macos_cmd.dart';

export 'package:server/server.dart';

const fs = f.LocalFileSystem();

/// The app's only entry point to clashyService.
///
/// clashyService is the Go process that owns mihomo: on desktop it is the
/// installed daemon behind `clashSocket`, on mobile it is the tunnel process
/// behind the socket [initTunnelSocket] resolves at start-up. Its wire protocol
/// lives in [ClashServiceApi], which stays inside this package: callers use the
/// methods below and never reach for the API object, so the socket choice, the
/// platform split and the response envelope are handled in one place.
///
/// Two groups of methods are deliberately platform-bound and no-op elsewhere:
/// desktop ones ([updateDesktopServiceIfOutdated], [hasOtherVpnConnection],
/// [close], [uninstall]) and mobile ones ([initTunnelSocket]). The rest either
/// route to the right platform backend or talk to whichever service the client
/// currently points at.
abstract final class ClashService {
  static bool get _isDesktop =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  /// Points [ClashServiceApi] at the mobile tunnel's control socket, once, at
  /// app start: the directory comes from the platform (the app's own on
  /// Android, the App Group copy on iOS, which the tunnel cannot reach from the
  /// app sandbox). Desktop keeps the daemon socket it already defaults to.
  static Future<void> initTunnelSocket({String? configDir}) async {
    final String? directory;
    if (Platform.isIOS) {
      directory = await IOSVpnService.sharedConfigDirectory;
    } else if (Platform.isAndroid) {
      directory = configDir;
    } else {
      directory = null;
    }
    if (directory == null) return;

    ClashServiceApi.socketPath = _clashControlSocket(directory);
  }

  /// Waits until the service answers. Android starts its core inside the
  /// `:vpn` process asynchronously (and may still be fetching GeoIP data), so
  /// the control socket shows up later than the start request returns.
  static Future<bool> waitForService({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await ClashServiceApi.isReady()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  static String _clashControlSocket(String configDir) {
    final direct = p.join(configDir, _controlSocketName);
    if (direct.length <= _maxUnixSocketPath) return direct;
    return p.join(p.dirname(configDir), _controlSocketName);
  }

  static const _controlSocketName = 'cs.sock';
  static const _maxUnixSocketPath = 100;

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
  static Future<bool> hasOtherVpnConnection() async {
    if (!Platform.isMacOS) return false;
    return MacOSServiceProcess.hasOtherVpnConnection();
  }

  /// Reinstalls the desktop service if its running version is older than this app.
  static Future<void> updateDesktopServiceIfOutdated({
    required String controllerSocketPath,
  }) async {
    if (!_isDesktop) return;
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
      final requested = await android.AndroidVpnService.start(
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
      if (!requested) return false;
      // Android establishes the TUN inside the `:vpn` process after the intent
      // returns; until then the platform still reports the previous state.
      return _waitForVpnState(true);
    }

    if (Platform.isIOS) {
      return IOSVpnService.start(profile);
    }

    if (_isDesktop) {
      if (!await _startDesktopService(
        controllerSocketPath: controllerSocketPath,
      )) {
        return false;
      }
      try {
        await _startDesktopCore(profile);
      } catch (e) {
        Log.e('starting the desktop core failed: $e');
        return false;
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
      await _waitUntilWindowsServiceReady();
      return true;
    }
    return false;
  }

  /// 等待 Windows 服务的控制管道可用，最多 2 秒。管道迟迟不就绪时由
  /// `_RetryInterceptor` 的重试退避兜底，所以这里只等、不判失败。
  static Future<void> _waitUntilWindowsServiceReady() async {
    for (var i = 0; i < 20; i++) {
      if (await ClashServiceApi.getServiceVersion() != null) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  static Future<ApiResp> reloadClashConfig() =>
      ClashServiceApi.reloadClashConfig();

  /// Whether the platform's VPN interface or tunnel is active.
  /// Waits until the platform reports [active].
  ///
  /// Android starts and stops its TUN asynchronously inside the `:vpn`
  /// process, so the state read right after the intent still belongs to the
  /// previous session. Callers that flip a switch would otherwise show the old
  /// value for a few seconds.
  static Future<bool> _waitForVpnState(
    bool active, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await isVpnActive() == active) return true;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return false;
  }

  static Future<bool> isVpnActive() async {
    if (Platform.isAndroid) return android.AndroidVpnService.isVpnActive();
    if (Platform.isIOS) return IOSVpnService.isActive();
    if (_isDesktop) return ClashServiceApi.isVpnActive();
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

    if (_isDesktop) {
      if (!await _startDesktopService(
        controllerSocketPath: controllerSocketPath,
      )) {
        return false;
      }
      await _startDesktopCore(profile);
      return true;
    }

    return false;
  }

  /// Starts the daemon's core unless it already runs; throws with the service's
  /// own message so callers can surface it.
  static Future<void> _startDesktopCore(ClashProfile profile) async {
    if (await ClashServiceApi.isClashRunning()) return;

    final response = await ClashServiceApi.startClashCore(profile);
    if (response.success) return;

    final details = response.data ?? response.msg;
    throw StateError(
      details == null || '$details'.isEmpty
          ? 'Desktop service failed to start the Clash core.'
          : 'Desktop service failed to start the Clash core: $details',
    );
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

  /// Hands [profile] to the running service and updates what it shows.
  ///
  /// The service owns the config and the refresh schedule, so the profile is
  /// only announced: Android also renames its notification title, while iOS and
  /// desktop have nothing else to update. Returns false when the service
  /// rejects the call, which means it is not running yet.
  static Future<bool> updateProfile(
    ClashProfile profile, {
    bool refresh = true,
    String? controllerSocketPath,
  }) async {
    final response = await ClashServiceApi.updateProfile(
      profile,
      refresh: refresh,
    );
    if (response?.success != true) return false;

    if (Platform.isAndroid) {
      await android.AndroidVpnService.updateProfile(
        profileName: profile.name ?? '',
        controllerSocketPath: controllerSocketPath,
      );
    }
    return true;
  }

  /// Tears the VPN service down.
  ///
  /// Linux 停止 systemd 服务但保留安装；Windows 停止 SCM 服务（未提权时
  /// 弹 UAC）。已停止时直接返回 `true`，不触发提权。
  static Future<bool> close() async {
    if (Platform.isAndroid) {
      final closed = await android.AndroidVpnService.close();
      if (!closed) return false;
      return _waitForVpnState(false);
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
      final stopped = await android.AndroidVpnService.stopVpn();
      if (!stopped) return false;
      return _waitForVpnState(false);
    }
    if (Platform.isIOS) {
      return IOSVpnService.close();
    }

    if (!_isDesktop) return false;

    try {
      return (await ClashServiceApi.stopVpn()).success;
    } catch (e) {
      Log.e('stopping the desktop VPN failed: $e');
      return false;
    }
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
