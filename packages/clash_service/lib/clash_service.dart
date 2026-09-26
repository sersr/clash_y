import 'dart:io';

import 'package:clash_service/src/service/clash_service_macos.dart';
import 'package:clash_service_android/clash_service_android.dart' as android;
import 'package:file/local.dart' as f;

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
      final res = DaemonStatusMacOS.daemonStatus(vpnServiceRegisterHelper());

      return res == .enabled;
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
      final DaemonStatusMacOS res = .daemonStatus(vpnServiceUnregisterHelper());
      return res == .notRegistered;
    }

    return false;
  }
}
