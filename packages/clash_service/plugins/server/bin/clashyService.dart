// ignore_for_file: file_names

import 'dart:io';
import 'dart:isolate';

import 'package:clash_service/src/service/clash_service_windows.dart';
import 'package:server/server.dart';
import 'package:server/src/server/clash_process.dart';

// Future<void> _install() async {
//   if (Platform.isLinux) {
//     final res = await installSystemdService();
//     exit(res);
//   } else if (Platform.isWindows) {
//     final ok = installService();
//     stdout.writeln(ok ? '服务安装成功: $windowService' : '服务安装失败（请以管理员身份运行）');
//     exit(ok ? 0 : 1);
//   }
// }

// Future<void> _unInstall() async {
//   if (Platform.isLinux) {
//     final res = await stopSystemdService();
//     exit(res);
//   } else if (Platform.isWindows) {
//     final ok = uninstallService();
//     stdout.writeln(ok ? '服务已卸载: $windowService' : '服务卸载失败（请以管理员身份运行）');
//     exit(ok ? 0 : 1);
//   }
// }

Future<void> main(List<String> args) async {
  // if (args case [var command, ...]) {
  //   switch (command) {
  //     case 'install':
  //       await _install();
  //     case 'uninstall':
  //       await _unInstall();
  //   }
  //   return;
  // }
  if (Platform.isWindows) {
    await Isolate.spawn((_) => clashServer(), null);
    await connectWindowScm();
    // 服务停止：强制退出，结束后台 clashServer isolate
    exit(0);
  }
  await clashServer();
  ClashProcess.run('./te');
}
