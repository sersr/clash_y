// ignore_for_file: file_names

import 'dart:io';
import 'dart:isolate';

import 'package:clash_service/src/service/clash_service_windows.dart';
import 'package:clash_service/src/service/clash_service_linux.dart';
import 'package:server/server.dart';
import 'package:server/src/server/clash_process.dart';

Future<void> _install() async {
  if (Platform.isLinux) {
    final res = await installSystemdService();
    exit(res);
  } else if (Platform.isWindows) {
    installService();
  }
}

Future<void> _unInstall() async {
  if (Platform.isLinux) {
    final res = await stopSystemdService();
    exit(res);
  } else if (Platform.isWindows) {
    uninstallService();
  }
}

Future<void> main(List<String> args) async {
  if (args case [var command, ...]) {
    switch (command) {
      case 'install':
        _install();
      case 'uninstall':
        _unInstall();
    }
    return;
  }
  if (Platform.isWindows) {
    await Isolate.spawn((_) => clashServer(), null);
    connectWindowScm();
    return;
  }
  await clashServer();
  ClashProcess.run('./te');
}
