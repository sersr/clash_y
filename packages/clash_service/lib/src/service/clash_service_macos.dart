library;

import 'dart:ffi';

@Native<Int32 Function()>(symbol: 'vpn_service_register_helper')
external int vpnServiceRegisterHelper();

@Native<Int32 Function()>(symbol: 'vpn_service_unregister_helper')
external int vpnServiceUnregisterHelper();

enum DaemonStatusMacOS {
  notRegistered,
  enabled,
  requiresApproval,
  notFound,
  none;

  static DaemonStatusMacOS daemonStatus(int index) {
    if (index < 0 || index > values.length - 1) return .none;
    return values[index];
  }
}
