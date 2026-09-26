// ignore_for_file: file_names

import 'dart:io';
import 'dart:isolate';

import 'package:clash_service/src/service/clash_service_windows.dart';
import 'package:server/server.dart';

Future<void> main() async {
  if (Platform.isWindows) {
    await Isolate.spawn((_) => clashServer(), null);
    connectWindowScm(windowService);
    return;
  }
  await clashServer();
}
