import 'dart:async';
import 'dart:io';

import 'package:nop/nop.dart';
import 'package:path/path.dart';

mixin ClashProcessMixin on ListenMixin, Resolve {
  Process? _process;
  String get appPath;
  String get clashDir => join(appPath, 'config');

  late String dir;

  // void regSetKeyValue(bool enable) {
  //   final subKey = TEXT(
  //     "Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings",
  //   );

  //   final word = calloc<DWORD>()..value = enable ? 1 : 0;
  //   final https = TEXT(proxyPort);
  //   final enableName = TEXT('ProxyEnable');
  //   final serverName = TEXT('ProxyServer');

  //   RegSetKeyValue(HKEY_CURRENT_USER, subKey, enableName, REG_DWORD, word, 4);

  //   RegSetKeyValue(
  //     HKEY_CURRENT_USER,
  //     subKey,
  //     serverName,
  //     REG_SZ,
  //     https,
  //     https.length * 2,
  //   );
  //   free(word);
  //   free(https);
  //   free(enableName);
  //   free(serverName);
  // }

  @override
  FutureOr<void> onClose() {
    // regSetKeyValue(false);
    _process?.kill();
    _process = null;
    return super.onClose();
  }
}
