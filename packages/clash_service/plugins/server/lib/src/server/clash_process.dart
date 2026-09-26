import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';

import 'package:clash_core/clash_core.dart';
import 'package:ffi/ffi.dart';
import 'package:nop/nop.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart' as web;
import 'package:web_socket_channel/web_socket_channel.dart';

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
    final router = Router();
    router
      ..get('/ws', web.webSocketHandler(ClashProcess.ws))
      ..get('/', ClashProcess.getClash)
      ..post('/', ClashProcess.startClash);

    return Pipeline().addMiddleware(_decodeData).addHandler(router.call);
  }

  static RespHandler _decodeData(Handler handler) {
    return (Request request) async {
      if (request.headers case {'content-type': var type}
          when type != 'application/json') {
        return .error(msg: "content-type != application/json");
      }

      if (request.method == 'POST') {
        String? data;
        try {
          data = await request.readAsString();

          final jsonData = jsonDecode(data);
          request = request.change(context: {'clashy_data': jsonData});
        } catch (e) {
          if (data != null) {
            request = request.change(context: {'clashy_data': data});
          } else {
            return .error(msg: '$e');
          }
        }
      }

      return .new(await handler(request));
    };
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

    final res = await _run(configDir);

    return .ok(res);
  }

  static Future<String?> _run(String configDir) async {
    return _clashQueue.run(() => _runSingle(configDir));
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
}
