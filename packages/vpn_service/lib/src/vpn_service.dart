import 'package:flutter/services.dart';

import '../vpn_service_platform_interface.dart';

class VPNService extends VpnServicePlatform {
  static const MethodChannel methodChannel = MethodChannel('vpn_service');

  static Future<bool> start(
    String configDir, {
    List<String> allowedApplications = const [],
    List<String> disallowedApplications = const [],
  }) async {
    final value = await methodChannel.invokeMethod<bool>('start', {
      'configDir': configDir,
      'allowedApplications': allowedApplications,
      'disallowedApplications': disallowedApplications,
    });
    return value ?? false;
  }

  static Future<bool> close() async {
    final value = await methodChannel.invokeMethod<bool>('close');
    return value ?? false;
  }
}
