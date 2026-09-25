import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:nop/nop.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart' as web;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'base_info.dart';
import 'models/models.dart';
import 'response.dart';

Process? _process;

final _clashQueue = TaskQueue();

final class _ClashKey {
  _ClashKey({required this.args});
  final List<String> args;

  @override
  int get hashCode => const ListEquality().hash(args);

  @override
  bool operator ==(Object other) {
    if (other is! _ClashKey) return false;
    return other.runtimeType == runtimeType &&
        const ListEquality().equals(args, other.args);
  }
}

extension on Request {
  Map<String, dynamic> get data {
    final p = context['clashy_data'];
    if (p is Map<String, dynamic>) {
      return p;
    }
    return {};
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

    return Pipeline().addMiddleware(_checkJsonContent).addHandler(router.call);
  }

  static Handler _checkJsonContent(Handler handler) {
    return (Request request) async {
      if (request.headers case {'content-type': var type}
          when type != 'application/json') {
        return Resp.res(.error(msg: "content-type != application/json"));
      }

      if (request.method == 'POST') {
        try {
          final data = await request.readAsString();

          final jsonData = jsonDecode(data);
          if (jsonData is! Map) {
            return Resp.res(.error(msg: "data is not Map."));
          }

          request = request.change(
            context: {
              'clashy_data': UnmodifiableMapView(
                jsonData as Map<String, dynamic>,
              ),
            },
          );
        } catch (e) {
          return Resp.res(.error(msg: '$e'));
        }
      }

      return handler(request);
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
    return .res(.ok());
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
    return .res(
      .ok(
        jsonEncode({
          "dir": Platform.resolvedExecutable,
          'work': Directory.current.path,
        }),
      ),
      headers: jsonHeader,
    );
  }

  static Future<Resp> startClash(Request request) async {
    final req = ClashStartReq.fromJson(request.data);

    await _run(req.args);
    return .res(.ok());
  }

  static Future<void> _run(List<String> args) async {
    return _clashQueue.run(() => _runSingle(_ClashKey(args: args)));
  }

  static _ClashKey? _clashKey;
  static Future<void> _runSingle(_ClashKey data) async {
    if (_clashKey == data) {
      if (_process case var _?) {
        return;
      }
    }

    final process = await Process.start(
      currentExeDir.childFile('clash').path,
      data.args,
      workingDirectory: currentExeDir.path,
    );
    _process?.kill();
    _process = process;
    _clashKey = data;

    // process.stderr.forEach(stderr.add);
    // process.stdout.forEach(stdout.add);
    process.exitCode.whenComplete(() {
      if (_process == process) {
        _clashKey = null;
        _process?.kill();
        _process = null;
      }
    });
  }
}

final currentExeDir = fs.currentDirectory
    .childFile(Platform.resolvedExecutable)
    .parent;
