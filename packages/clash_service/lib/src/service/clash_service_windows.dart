import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

const windowService = 'clashy_service';

void connectWindowScm() {
  dartConnectService(windowService.toNativeUtf16());
}

void installService() {
  final current = Platform.resolvedExecutable;
  using((arena) {
    dartInstallService(
      windowService.toNativeUtf16(allocator: arena),
      windowService.toNativeUtf16(allocator: arena),
      'clashy service'.toNativeUtf16(allocator: arena),
      "".toNativeUtf16(allocator: arena),
      0x2,
      "".toNativeUtf16(allocator: arena),
      ffi.Pointer.fromAddress(0),
      ffi.Pointer.fromAddress(0),
      current.toNativeUtf16(allocator: arena),
      1,
      1,
      ffi.Pointer.fromAddress(0),
      1,
    );
  });
}

void uninstallService() {
  using((arena) {
    dartUninstallService(windowService.toNativeUtf16(allocator: arena));
  });
}

typedef PCWSTR = ffi.Pointer<Utf16>;
typedef DWORD = ffi.UnsignedLong;

typedef CDartInstallService = ffi.Void Function(
  PCWSTR pszServiceName,
  PCWSTR pszDisplayName,
  PCWSTR pszDescription,
  PCWSTR pszParams,
  DWORD dwStartType,
  PCWSTR pszDependencies,
  PCWSTR pszAccount,
  PCWSTR pszPassword,
  PCWSTR serviceCallPath,
  ffi.Int bRegisterWithEventLog,
  DWORD dwNumMessageCategories,
  PCWSTR pszMessageResourceFilePath,
  ffi.Int delayedStart,
);

typedef DartInstallService = void Function(
  PCWSTR pszServiceName,
  PCWSTR pszDisplayName,
  PCWSTR pszDescription,
  PCWSTR pszParams,
  int dwStartType,
  PCWSTR pszDependencies,
  PCWSTR pszAccount,
  PCWSTR pszPassword,
  PCWSTR serviceCallPath,
  int bRegisterWithEventLog,
  int dwNumMessageCategories,
  PCWSTR pszMessageResourceFilePath,
  int delayedStart,
);

typedef CDartConnectService = ffi.Void Function(PCWSTR);
typedef DartConnectService = void Function(PCWSTR);

typedef CDartUninstallService = ffi.Void Function(PCWSTR);
typedef DartUninstallService = void Function(PCWSTR);

@ffi.Native<CDartInstallService>(symbol: 'DartInstallService')
external void dartInstallService(
  PCWSTR pszServiceName,
  PCWSTR pszDisplayName,
  PCWSTR pszDescription,
  PCWSTR pszParams,
  int dwStartType,
  PCWSTR pszDependencies,
  PCWSTR pszAccount,
  PCWSTR pszPassword,
  PCWSTR serviceCallPath,
  int bRegisterWithEventLog,
  int dwNumMessageCategories,
  PCWSTR pszMessageResourceFilePath,
  int delayedStart,
);

@ffi.Native<CDartConnectService>(symbol: 'DartConnectService')
external void dartConnectService(PCWSTR name);
@ffi.Native<CDartUninstallService>(symbol: 'DartUninstallService')
external void dartUninstallService(PCWSTR name);
