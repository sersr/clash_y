import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:file/local.dart';
import 'package:nop_db/isolate_event.dart';
import 'package:path/path.dart';
import 'package:process/process.dart';
import 'package:utils/utils.dart';
import 'package:win32/win32.dart';

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

    Log.i('dir: $dir', onlyDebug: false);
    final docPath =
        fs.currentDirectory.childDirectory(clashDir).childFile('config.yaml');
    if (!docPath.existsSync()) {
      Log.w(docPath);
      final configFile =
          fs.currentDirectory.childDirectory(f).parent.childFile('config.yaml');
          Log.w(configFile);
      if (configFile.existsSync()) {
        configFile.copySync(docPath.path);
      }
    }
    _process = await const LocalProcessManager().start(
        ['$dir/clash.exe', '-d', clashDir],
        mode: ProcessStartMode.detachedWithStdio);
    _process?.stdout.transform(utf8.decoder).listen((event) {
      Log.i(event, onlyDebug: false);
    });
    regSetKeyValue(true);
    await onClashInit();
  }

  Future<void> onClashInit() async {}

  void _findWindow(String name) {
    final cstr = TEXT(name);
    final hwnd = FindWindow(nullptr, cstr);
    final showText = TEXT('找到窗口');
    final title = TEXT('find');
    if (IsWindow(hwnd) == TRUE) {
      MessageBox(hwnd, showText, title, MB_OK);
    }
    free(showText);
    free(title);
    free(cstr);
  }

  void regSetKeyValue(bool enable) {
    final subKey =
        TEXT("Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings");

    final word = calloc<DWORD>()..value = enable ? 1 : 0;
    final https = TEXT(proxyPort);
    final enableName = TEXT('ProxyEnable');
    final serverName = TEXT('ProxyServer');

    RegSetKeyValue(HKEY_CURRENT_USER, subKey, enableName, REG_DWORD, word, 4);

    RegSetKeyValue(
        HKEY_CURRENT_USER, subKey, serverName, REG_SZ, https, https.length * 2);
    free(word);
    free(https);
    free(enableName);
    free(serverName);
  }

  @override
  FutureOr<bool> onClose() {
    regSetKeyValue(false);
    _process?.kill();
    _process = null;
    return super.onClose();
  }
}
