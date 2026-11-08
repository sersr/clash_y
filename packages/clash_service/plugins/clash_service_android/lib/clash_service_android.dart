/// Android VPN backend for `package:clash_service`.
///
/// Implemented with JNIgen, `package:jni`, and `package:jni_flutter`: the VPN
/// consent flow, service intent, and service start/stop calls happen in Dart,
/// while the Android VpnService component is implemented in Kotlin.
library;

import 'src/android_vpn_service.dart';

export 'src/android_vpn_service.dart' show AndroidVpnService;

/// Starts the bundled VPN service with [configDir] as mihomo's configuration
/// directory.
///
/// [allowList] enables per-application allow-list routing. The Android service
/// also adds its own package, which owns the TUN, to that list.
///
/// Returns `false` when the platform is not Android, when [configDir] is empty,
/// when the user rejects the VPN consent dialog, or when the foreground service
/// could not be started.
///
/// A `true` result means the service was asked to start. mihomo loads its
/// configuration asynchronously, so callers that depend on mihomo itself should
/// poll its API until it answers.
Future<bool> start(
  String configDir, {
  String? profileName,
  String? controllerSocketPath,
  bool allowList = false,
  List<String> allowedApplications = const <String>[],
  List<String> disallowedApplications = const <String>[],
}) {
  return AndroidVpnService.start(
    configDir,
    profileName: profileName,
    controllerSocketPath: controllerSocketPath,
    allowList: allowList,
    allowedApplications: allowedApplications,
    disallowedApplications: disallowedApplications,
  );
}

/// Stops the VPN service and releases the TUN device it owns.
Future<bool> stop() => AndroidVpnService.close();
