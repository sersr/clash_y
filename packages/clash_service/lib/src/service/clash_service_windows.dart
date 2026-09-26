import 'dart:ffi';

import 'package:dart_windows_service_support/dart_windows_service_support.dart';
import 'package:ffi/ffi.dart';

final DartConnectServiceDLL serviceDLL = .new('WindowsServiceDLL64.dll');

const windowService = 'clashy_service';

void connectWindowScm(String service) {
  serviceDLL.dartConnectService(service.toNativeUtf16().cast<Uint16>());
}

void installService(String service, String servicePath, String desc) {
  using((arena) {
    serviceDLL.dartInstallService(
      service.toNativeUtf16(allocator: arena).cast(),
      service.toNativeUtf16(allocator: arena).cast(),
      desc.toNativeUtf16(allocator: arena).cast(),
      "".toNativeUtf16(allocator: arena).cast<Uint16>(),
      0x2,
      "".toNativeUtf16(allocator: arena).cast<Uint16>(),
      Pointer.fromAddress(0),
      Pointer.fromAddress(0),
      servicePath.toNativeUtf16(allocator: arena).cast<Uint16>(),
      1,
      1,
      Pointer.fromAddress(0),
      1,
    );
  });
}

void uninstallService(String service) {
  using((arena) {
    serviceDLL.dartUninstallService(
      service.toNativeUtf16(allocator: arena).cast<Uint16>(),
    );
  });
}
