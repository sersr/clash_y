// ignore_for_file: file_names

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:server/clash_service_windows.dart';
import 'package:server/server.dart';
import 'package:server/src/server/clash_process.dart';
import 'package:server/tray_asset.dart';

Future<void> main(List<String> args) async {
  if (Platform.isWindows) {
    if (args.contains('cmd')) {
      return clashServer();
    }
    await Isolate.spawn((_) => clashServer(), null);
    await connectWindowScm();
    // 服务停止：强制退出，结束后台 clashServer isolate
    exit(0);
  }
  if (Platform.isMacOS) {
    await _runMacOSService((
      _requiredArgument(args, '--app'),
      _requiredArgument(args, '--service-socket'),
      _requiredArgument(args, '--clash-socket'),
    ));
    return;
  }
  await clashServer();
}

Future<void> _runMacOSService((String, String, String) options) async {
  final (appPath, serviceSocket, clashSocket) = options;
  Process? trayProcess;
  var shuttingDown = false;

  try {
    final trayPath = p.join(
      p.dirname(Platform.resolvedExecutable),
      clashTrayExecutableName,
    );
    try {
      trayProcess = await Process.start(trayPath, [
        '--app',
        appPath,
        '--service-socket',
        serviceSocket,
        '--clash-socket',
        clashSocket,
      ], workingDirectory: appPath);
      trayProcess.stdout.transform(utf8.decoder).listen(stderr.write);
      trayProcess.stderr.transform(utf8.decoder).listen(stderr.write);
      trayProcess.exitCode.then((code) {
        stderr.writeln('Clashy Tray exited with code $code');
      });
    } catch (error, stackTrace) {
      stderr.writeln(
        'start Clashy Tray executable failed: $error\n$stackTrace',
      );
    }

    ProcessSignal.sigterm.watch().listen((_) async {
      if (shuttingDown) return;
      shuttingDown = true;
      trayProcess?.kill();
      try {
        final error = await ClashProcess.stop();
        if (error != null) {
          stderr.writeln('stop Clash before exiting failed: $error');
        }
      } catch (error, stackTrace) {
        stderr.writeln('stop Clash before exiting failed: $error\n$stackTrace');
      } finally {
        exit(0);
      }
    });
    await clashServer();
  } catch (error, stackTrace) {
    stderr.writeln('clashyService failed: $error\n$stackTrace');
    exit(1);
  }
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
