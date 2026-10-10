import 'dart:io';

import 'package:clash_service_android/clash_service_android.dart' as android;
import 'package:file/local.dart' as f;

import 'src/service/clash_service_macos_cmd.dart';

export 'package:server/server.dart';

export 'src/service/clash_service_windows.dart';

const fs = f.LocalFileSystem();

abstract final class ClashService {
  /// Brings the VPN service up for the configuration in [configDir].
  ///
  /// Returns `false` on platforms without a VPN backend, and when the platform
  /// backend refuses to start — for example because the user declined the
  /// Android VPN consent dialog.
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

    // iOS, Linux and Windows have no VPN backend wired up here. The macOS
    // helper above and the Android plugin are the only implementations.
    return false;
  }

  /// Tears the VPN service down.
  static Future<bool> close() async {
    if (Platform.isAndroid) {
      return android.AndroidVpnService.close();
    }

    if (Platform.isMacOS) {
      if (!await HelperInstaller.isRunning()) return true;

      await HelperInstaller.stop();
      return !await HelperInstaller.isRunning();
    }

    return false;
  }

  static Future<bool> uninstall() async {
    if (Platform.isAndroid) {
      return android.AndroidVpnService.close();
    }

    if (Platform.isMacOS) {
      if (!await HelperInstaller.isInstalled()) return true;

      await HelperInstaller.uninstall();
      return !await HelperInstaller.isInstalled();
    }

    return false;
  }
}
