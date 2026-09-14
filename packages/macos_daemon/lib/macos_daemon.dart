import 'package:flutter/services.dart';

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

class VPNService {
  static const MethodChannel _channel = MethodChannel('macos_daemon');

  static VPNStatus? _toVpnStatus(dynamic value) {
    if (value case {'status': int status, "error": String error}) {
      return VPNStatus(status, value['msg'], error, value['pid']);
    }

    print('VPNService error: $value');
    return null;
  }

  static Future<VPNStatus?> installHelper() async {
    final value = await _channel.invokeMethod('installHelper');

    return _toVpnStatus(value);
  }

  static Future<VPNStatus?> unregister() async {
    final value = await _channel.invokeMethod('unregister');

    return _toVpnStatus(value);
  }

  static Future<VPNStatus?> start(String configPath) async {
    final value = await _channel.invokeMethod('start', {
      'configPath': configPath,
    });

    return _toVpnStatus(value);
  }

  static Future<VPNStatus?> stop() async {
    final value = await _channel.invokeMethod('stop');

    return _toVpnStatus(value);
  }
}
