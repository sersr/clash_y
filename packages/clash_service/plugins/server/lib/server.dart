import 'dart:io';

import 'package:dart_ipc/dart_ipc.dart';
import 'package:nop/utils.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

import 'src/server/base_info.dart';
import 'src/server/clash_process.dart';

export 'src/server/response.dart';
export 'src/server/models/models.dart';

final router = Router()
  ..get('/', (Request req) => Response.ok('Clash VPN!'))
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

Future<void> main() async {
  Log.defaultLogger.logPathFn = (path) => path;

  final handler = const Pipeline()
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
