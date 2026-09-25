library;

import 'dart:ffi';

@Native<Int32 Function()>(symbol: 'vpn_service_register_helper')
external int vpnServiceRegisterHelper();

@Native<Int32 Function()>(symbol: 'vpn_service_unregister_helper')
external int vpnServiceUnregisterHelper();
