import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:clash_core/clash_core.dart';
import 'package:ffi/ffi.dart';
import 'package:nop/nop.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart' as web;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../my_router.dart';
import 'response.dart';

final _clashQueue = TaskQueue();

extension on Request {
  dynamic get data {
    return context['clashy_data'];
  }
}

abstract final class ClashProcess {
  static final _sockets = <WebSocketChannel>[];
  static final _sockets2 = <StreamSink<List<int>>>[];
  static Handler get clash {
    final router = MyRouter();
    router
      ..ws('/ws', web.webSocketHandler(ws))
      ..get('/', getClash)
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

  static Future<Resp> startClash(Request request) async {
    final configDir = request.data as String;

    final res = await run(configDir);

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

    String? err;
    _started = false;
    using((arena) {
      try {
        final res = start(configDir.toNativeUtf8(allocator: arena).cast());
        if (res != nullptr) {
          final error = res.cast<Utf8>().toDartString();
          if (error.isNotEmpty) {
            err = error;
            Log.e('start Error: $e');
          }
          freeString(res);
          _started = false;
        } else {
          _started = true;
        }
      } catch (e) {
        Log.e('start error: $e');
      }
    });

    _clashKey = configDir;

    return err;
  }

  static Future<String?> _stopSingle() async {
    String? err;
    _started = false;
    _clashKey = null;

    using((arena) {
      try {
        final res = stop();
        if (res != nullptr) {
          final error = res.cast<Utf8>().toDartString();
          if (error.isNotEmpty) {
            err = error;
            Log.e('start Error: $e');
          }
          freeString(res);
          _started = false;
        } else {
          _started = true;
        }
      } catch (e) {
        Log.e('start error: $e');
      }
    });

    return err;
  }
}
