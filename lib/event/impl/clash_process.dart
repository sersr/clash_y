import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file/local.dart';
import 'package:nop/nop.dart';
import 'package:path/path.dart';
import 'package:process/process.dart';

mixin ClashProcessMixin on ListenMixin, Resolve {
  Process? _process;
  String get proxyPort;
  String get clashRoot;
  String get clashDir => join(clashRoot, 'config');
  @override
  void initStateListen(add) {
    super.initStateListen(add);
    add(_init());
  }

  late String dir;
  Future<void> _init() async {
    const fs = LocalFileSystem();
    final f = Platform.resolvedExecutable;
    dir = fs.currentDirectory.childDirectory(f).dirname;

    Log.i('dir: $dir');
    final docPath = fs.currentDirectory
        .childDirectory(clashDir)
        .childFile('config.yaml');
    if (!docPath.existsSync()) {
      Log.w(docPath);
      final configFile = fs.currentDirectory
          .childDirectory(f)
          .parent
          .childFile('config.yaml');
      Log.w(configFile);
      if (configFile.existsSync()) {
        configFile.copySync(docPath.path);
      }
    }
    _process = await const LocalProcessManager().start([
      '$dir/clash.exe',
      '-d',
      clashDir,
    ], mode: ProcessStartMode.detachedWithStdio);
    _process?.stdout.transform(utf8.decoder).listen((event) {
      Log.i(event);
    });
    // regSetKeyValue(true);
    await onClashInit();
  }

  Future<void> onClashInit() async {}

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
