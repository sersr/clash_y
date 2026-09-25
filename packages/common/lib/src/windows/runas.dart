import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

bool shellExecute({
  required String operation,
  required String file,
  String? parameters,
}) {
  return using((arena) {
    final result = ShellExecute(
      HWND(nullptr),
      arena.pcwstr(operation),
      arena.pcwstr(file),
      parameters == null ? PCWSTR(nullptr) : arena.pcwstr(parameters),
      PCWSTR(nullptr),
      SW_SHOWNORMAL,
    );
    if (result.address <= 32) {
      return false;
    }
    return true;
  });
}
