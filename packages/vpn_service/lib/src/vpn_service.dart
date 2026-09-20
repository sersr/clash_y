import 'package:flutter/services.dart';

import '../vpn_service_platform_interface.dart';

class VPNService extends VpnServicePlatform {
  static const MethodChannel methodChannel = MethodChannel('vpn_service');

  static Future<bool> start(String configDir) async {
    final value = await methodChannel.invokeMethod<bool>('start', {
      'configDir': configDir,
    });
    return value ?? false;
  }

  static Future<bool> close() async {
    final value = await methodChannel.invokeMethod<bool>('close');
    return value ?? false;
  }
}
