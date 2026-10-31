import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:clash_core/clash_core.dart';
import 'package:ffi/ffi.dart';
import 'package:nop/nop.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart' as web;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:yaml/yaml.dart';

import '../my_router.dart';
import 'response.dart';

final _clashQueue = TaskQueue();

extension on Request {
  dynamic get data {
    return context['clashy_data'];
  }
}

abstract final class ClashProcess {
  static const _wakeNetworkSettleDelay = Duration(seconds: 5);
  static const _stateFilePath =
      '/Library/Application Support/Clashy/clash-state.json';
  static const _wakeMonitorLibraryPath =
      '/Library/PrivilegedHelperTools/com.aote.clashy.helper.wake';

  static final _sockets = <WebSocketChannel>[];
  static final _sockets2 = <StreamSink<List<int>>>[];
  static final _stateFile = File(_stateFilePath);
  static ReceivePort? _wakeEvents;
  static StreamSubscription<dynamic>? _wakeSubscription;
  static Isolate? _wakeMonitor;
  static bool _recoveringTunAfterWake = false;
  static String? _tunInterface;

  static Future<void> restorePersistedClash() async {
    if (!Platform.isMacOS || !await _stateFile.exists()) return;

    try {
      final state = jsonDecode(await _stateFile.readAsString());
      if (state is! Map || state['configDir'] is! String) {
        Log.e('saved Clash state is invalid');
        return;
      }

      final configDir = state['configDir'] as String;
      Log.w('restoring Clash from saved state');
      final error = await run(configDir);
      if (error != null) {
        Log.e('restore Clash from saved state failed: $error');
      }
    } catch (e) {
      Log.e('restore Clash from saved state failed: $e');
    }
  }

  static Future<void> _persistConfigDir(String configDir) async {
    if (!Platform.isMacOS) return;

    await _stateFile.parent.create(recursive: true);
    final temporaryFile = File('$_stateFilePath.tmp');
    await temporaryFile.writeAsString(
      jsonEncode({'configDir': configDir}),
      flush: true,
    );
    await temporaryFile.rename(_stateFilePath);
  }

  static Future<void> _clearPersistedConfigDir() async {
    if (!Platform.isMacOS || !await _stateFile.exists()) return;
    await _stateFile.delete();
  }

  static Future<void> initialize() async {
    try {
      await startMacOSWakeMonitor();
    } catch (e) {
      Log.e('start macOS wake monitor failed: $e');
    }
    await restorePersistedClash();
  }

  static Future<void> startMacOSWakeMonitor() async {
    if (!Platform.isMacOS ||
        _wakeMonitor != null ||
        _wakeEvents != null ||
        _wakeSubscription != null) {
      return;
    }
    if (!await File(_wakeMonitorLibraryPath).exists()) {
      throw StateError('wake monitor library is not installed');
    }

    final events = ReceivePort();
    _wakeEvents = events;
    _wakeSubscription = events.listen((message) {
      if (message == 'wake') {
        unawaited(_recoverTunAfterWake());
      } else if (message is Map && message['error'] is String) {
        Log.e('macOS wake monitor failed: ${message['error']}');
      }
    });
    _wakeMonitor = await Isolate.spawn(
      _watchMacOSWake,
      events.sendPort,
      debugName: 'clashy-macos-wake-monitor',
    );
  }

  @pragma('vm:entry-point')
  static void _watchMacOSWake(SendPort sendPort) {
    try {
      final library = DynamicLibrary.open(_wakeMonitorLibraryPath);
      final start = library.lookupFunction<Int32 Function(), int Function()>(
        'clashy_wake_monitor_start',
      );
      final wait = library.lookupFunction<Int32 Function(), int Function()>(
        'clashy_wake_monitor_wait',
      );
      if (start() != 0) {
        throw StateError('IOKit power notification registration failed');
      }

      sendPort.send('ready');
      while (true) {
        if (wait() != 0) {
          throw StateError('IOKit wake notification wait failed');
        }
        sendPort.send('wake');
      }
    } catch (e) {
      sendPort.send({'error': '$e'});
    }
  }

  static Future<void> _recoverTunAfterWake() async {
    final configDir = _clashKey;
    if (_recoveringTunAfterWake || !_started || configDir == null) return;

    _recoveringTunAfterWake = true;
    try {
      final configFile = File('$configDir${Platform.pathSeparator}config.yaml');
      final config = loadYaml(await configFile.readAsString());
      final tun = config is Map ? config['tun'] : null;
      if (tun is! Map || tun['enable'] != true) return;

      if (await _isTunHealthy()) {
        Log.i('TUN is healthy after system wake; no restart needed');
        return;
      }

      Log.w('system wake detected; TUN is unavailable, restoring it');
      await Future<void>.delayed(_wakeNetworkSettleDelay);
      await _clashQueue.run(() async {
        if (!_started || _clashKey != configDir) return;

        final stopError = await _stopSingle();
        if (stopError != null) {
          Log.e('restore TUN after wake: stop failed: $stopError');
          return;
        }

        final startError = await _runSingle(configDir);
        if (startError != null) {
          Log.e('restore TUN after wake: start failed: $startError');
          return;
        }

        Log.w('TUN restored after system wake');
      });
    } catch (e) {
      Log.e('restore TUN after wake failed: $e');
    } finally {
      _recoveringTunAfterWake = false;
    }
  }

  static Future<bool> _isTunHealthy() async {
    final tunInterface = _tunInterface;
    if (tunInterface == null) {
      Log.w('unable to verify TUN interface; skipping wake recovery');
      return true;
    }

    final result = await Process.run('/sbin/ifconfig', [tunInterface]);
    if (result.exitCode != 0) return false;

    final output = result.stdout as String;
    final firstLine = output.split('\n').firstOrNull ?? '';
    return RegExp(r'flags=\d+<[^>]*\bUP\b').hasMatch(firstLine);
  }

  static Handler get clash {
    final router = MyRouter();
    router
      ..ws('/ws', web.webSocketHandler(ws))
      ..get('/', getClash)
      ..get('/status', getStatus)
      ..post('/', startClash)
      ..post('/stop', stopClash);

    return router.call;
  }

  static Future<Resp> ws(
    WebSocketChannel webSocket,
    String? subprotocol,
  ) async {
    _sockets.add(webSocket);
    webSocket.stream.listen(
      (data) {
        print(data);
      },
      cancelOnError: true,
      onDone: () => _sockets.remove(webSocket),
      onError: (_) => _sockets.remove(webSocket),
    );
    _start();
    return .ok();
  }

  static Timer? _timer;
  static void _start() {
    _timer?.cancel();
    Log.w('sockets: ${_sockets.length}');
    if (_sockets.isEmpty && _sockets2.isEmpty) return;
    for (var socket in _sockets) {
      socket.sink.add("value: ${Random().nextInt(1024)}");
    }
    for (var socket in _sockets2) {
      socket.add(utf8.encode("value: ${Random().nextInt(1024)}"));
    }
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 1), _start);
  }

  static Future<Resp> getClash(Request request) async {
    return .ok(
      jsonEncode({
        "dir": Platform.resolvedExecutable,
        'work': Directory.current.path,
      }),
    );
  }

  static Future<Resp> getStatus(Request request) async => .ok(_started);

  static Future<Resp> startClash(Request request) async {
    final configDir = request.data as String;

    final res = await run(configDir);
    if (res case String error when error.isNotEmpty) {
      return .error(data: error);
    }
    await _persistConfigDir(configDir);
    return .ok(res);
  }

  static Future<String?> run(String configDir) async {
    return _clashQueue.run(() => _runSingle(configDir));
  }

  static Future<Resp> stopClash(Request request) async {
    final err = await _clashQueue.run(_stopSingle);
    if (err case var err? when err.isNotEmpty) {
      return .error(data: err);
    }
    await _clearPersistedConfigDir();
    return .ok();
  }

  static String? _clashKey;
  static var _started = false;
  static Future<String?> _runSingle(String configDir) async {
    if (_clashKey == configDir) {
      if (_started) {
        return null;
      }
    }

    final interfacesBeforeStart = Platform.isMacOS
        ? await _listTunInterfaces()
        : const <String>{};

    String? err;
    _started = false;
    using((arena) {
      try {
        final res = start(configDir.toNativeUtf8(allocator: arena).cast());
        if (res != nullptr) {
          final error = res.cast<Utf8>().toDartString();
          if (error.isNotEmpty) {
            err = error;
            Log.e('start Error: $error');
          }
          freeString(res);
          _started = false;
        } else {
          _started = true;
        }
      } catch (e) {
        Log.e('start error: $e');
        err = e.toString();
      }
    });

    _clashKey = configDir;
    if (err == null && _started && Platform.isMacOS) {
      final interfacesAfterStart = await _listTunInterfaces();
      final createdInterface = interfacesAfterStart
          .difference(interfacesBeforeStart)
          .firstOrNull;
      if (createdInterface != null) {
        _tunInterface = createdInterface;
      } else if (_tunInterface != null &&
          !interfacesAfterStart.contains(_tunInterface)) {
        _tunInterface = null;
      }
      if (_tunInterface == null) {
        Log.w('unable to identify Clash TUN interface after start');
      }
    }

    return err;
  }

  static Future<Set<String>> _listTunInterfaces() async {
    final result = await Process.run('/sbin/ifconfig', ['-l']);
    if (result.exitCode != 0) {
      throw ProcessException(
        '/sbin/ifconfig',
        const ['-l'],
        '${result.stderr}',
        result.exitCode,
      );
    }

    return (result.stdout as String)
        .trim()
        .split(RegExp(r'\s+'))
        .where((name) => name.startsWith('utun'))
        .toSet();
  }

  static Future<String?> _stopSingle() async {
    String? err;
    final wasStarted = _started;

    using((arena) {
      try {
        final res = stopTun();
        if (res != nullptr) {
          final error = res.cast<Utf8>().toDartString();
          if (error.isNotEmpty) {
            err = error;
            Log.e('stop Error: $error');
          }
          freeString(res);
          _started = err != null ? wasStarted : false;
        } else {
          _started = false;
        }
      } catch (e) {
        Log.e('stop error: $e');
        _started = wasStarted;
      }
    });

    if (!_started) _clashKey = null;

    return err;
  }
}
