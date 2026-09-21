import 'package:flutter/services.dart';

import '../vpn_service_platform_interface.dart';

enum VPNType { notRegistered, enabled, requiresApproval, notFound }

final class VPNStatus {
  final int status;
  final String error;
  final String? msg;
  final int? pid;

  VPNStatus(this.status, this.msg, this.error, this.pid);

  @override
  String toString() {
    if (error.isNotEmpty) {
      return "status: $status, error: $error, pid: $pid";
    }
    return 'status: $status, msg: $msg, pid: $pid';
  }
}

class VPNService extends VpnServicePlatform {
  static const MethodChannel methodChannel = MethodChannel('vpn_service');

  static VPNStatus? _toVpnStatus(dynamic value) {
    if (value case {'status': int status, "error": String error}) {
      return VPNStatus(status, value['msg'], error, value['pid']);
    }

    print('VPNService error: $value');
    return null;
  }

  static Future<VPNStatus?> installHelper() async {
    final value = await methodChannel.invokeMethod('installHelper');

    return _toVpnStatus(value);
  }

  static Future<VPNStatus?> unregister() async {
    final value = await methodChannel.invokeMethod('unregister');

    return _toVpnStatus(value);
  }

  static Future<VPNStatus?> start(String configDir) async {
    final value = await methodChannel.invokeMethod('start', {
      'configDir': configDir,
    });

    return _toVpnStatus(value);
  }

  static Future<VPNStatus?> stop() async {
    final value = await methodChannel.invokeMethod('stop');

    return _toVpnStatus(value);
  }
}
