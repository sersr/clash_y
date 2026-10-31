import 'dart:async';
import 'dart:convert';
import 'dart:io';

abstract final class ClashTrayProcess {
  static const _configPath = '/Library/Application Support/Clashy/tray.json';

  static Process? _process;
  static String? _startedInstance;

  static Future<bool> configure(dynamic input) async {
    if (!Platform.isMacOS) return false;

    final request = input as Map<String, dynamic>;
    final config = <String, String>{
      'path': request['path'] as String,
      'appPath': request['appPath'] as String,
      'serviceSocket': request['serviceSocket'] as String,
      'clashSocket': request['clashSocket'] as String,
    };
    final file = File(_configPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(config), flush: true);

    await _start(config);
    return true;
  }

  static Future<void> startSaved() async {
    if (!Platform.isMacOS) return;
    final file = File(_configPath);
    if (!await file.exists()) return;

    final config = (jsonDecode(await file.readAsString()) as Map)
        .cast<String, String>();
    await _start(config);
  }

  static Future<void> _start(Map<String, String> config) async {
    final instance = config['path']!;
    if (_startedInstance == instance && _process != null) return;

    await stop();
    final process = await Process.start(config['path']!, [
      '--app',
      config['appPath']!,
      '--service-socket',
      config['serviceSocket']!,
      '--clash-socket',
      config['clashSocket']!,
    ]);
    _process = process;
    _startedInstance = instance;
    unawaited(
      process.exitCode.then((_) {
        if (identical(_process, process)) {
          _process = null;
          _startedInstance = null;
        }
      }),
    );
  }

  static Future<void> stop() async {
    final process = _process;
    if (process == null) return;

    process.kill();
    await process.exitCode;
    if (identical(_process, process)) {
      _process = null;
      _startedInstance = null;
    }
  }
}
