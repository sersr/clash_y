import 'dart:convert';
import 'dart:io';

import 'package:dart_ipc/dart_ipc.dart';
import 'package:nop/utils.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

import 'server.dart';
import 'src/my_router.dart';
import 'src/server/base_info.dart';
import 'src/server/clash_process.dart';

export 'src/server/models/models.dart';
export 'src/server/response.dart';

const version = '0.0.1';

final router = MyRouter()
  ..get('/', (req) => .ok('Clash VPN!'))
  ..get('/version', (req) => .ok(version))
  ..mount('/baseInfo', BaseInfo.router.call)
  ..mount('/clash', ClashProcess.clash);

Middleware loggingMiddleware() =>
    (Handler inner) => (Request req) async {
      final sw = Stopwatch()..start();
      final res = await inner(req);
      print(
        '${req.method} /${req.url.path} -> ${res.statusCode} (${sw.elapsedMilliseconds}ms)',
      );
      return res;
    };

RespHandler jsonMiddleware(Handler handler) {
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
    try {
      final res = await handler(request);
      return .new(res);
    } catch (e) {
      return .error(data: '$e');
    }
  };
}

Future<void> clashServer() async {
  Log.defaultLogger.logPathFn = (path) => path;
  await ClashProcess.initialize();

  final handler = const Pipeline()
      .addMiddleware(jsonMiddleware)
      .addMiddleware(loggingMiddleware())
      .addHandler(router.call);

  if (!Platform.isWindows) {
    final file = fs.currentDirectory.childFile(clashSocket);
    file.parent.createSync(recursive: true);

    try {
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {}
  }

  final server = HttpServer.listenOn(await bind(clashSocket));

  io.serveRequests(server, handler, poweredByHeader: 'clash VPN');

  if (!Platform.isWindows) {
    // 4. 设置权限（统一用 chmod / chown）
    await Process.run('chmod', ['666', clashSocket]);
    await Process.run('chown', ['root:wheel', clashSocket]);
    print('Serving at http://${server.address.host}:${server.port}');
  }
}

String get clashSocket {
  if (!Platform.isWindows) {
    return '/tmp/clashy/clash_service.sock';
  }

  return r'\\.\pipe\clashy\clash_service.pipe';
}
