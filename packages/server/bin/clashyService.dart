// ignore_for_file: file_names

import 'dart:io';
import 'dart:isolate';

import 'package:server/clash_service_windows.dart';
import 'package:server/server.dart';

Future<void> main(List<String> args) async {
  if (Platform.isWindows) {
    await Isolate.spawn((_) => clashServer(), null);
    await connectWindowScm();
    // 服务停止：强制退出，结束后台 clashServer isolate
    exit(0);
  }
  if (Platform.isMacOS) {
    configureMacOSRuntimeLibraries(
      clashLibraryPath: _requiredArgument(args, '--clash-library'),
    );
  }
  await clashServer();
}

String _requiredArgument(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 ||
      index + 1 >= args.length ||
      args[index + 1].startsWith('--')) {
    throw FormatException('Missing value for $name');
  }
  return args[index + 1];
}
