/// Android VPN backend for `package:clash_service`.
///
/// Implemented with `package:jni` and `package:jni_flutter`: the VPN consent
/// flow, the service intent, and the service start/stop calls all happen in
/// Dart, and only `ClashVpnService` itself lives on the Kotlin side.
library;

import 'src/android_vpn_service.dart';

export 'src/android_vpn_service.dart' show AndroidVpnService;

/// Starts the bundled VPN service with [configDir] as mihomo's configuration
/// directory.
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
  List<String> allowedApplications = const <String>[],
  List<String> disallowedApplications = const <String>[],
}) {
  return AndroidVpnService.start(
    configDir,
    allowedApplications: allowedApplications,
    disallowedApplications: disallowedApplications,
  );
}

/// Stops the VPN service and releases the TUN device it owns.
Future<bool> stop() => AndroidVpnService.close();
