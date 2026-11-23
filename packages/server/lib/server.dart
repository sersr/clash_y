import 'dart:convert';
import 'dart:io';

import 'package:dart_ipc/dart_ipc.dart';
import 'package:nop/utils.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

import 'server.dart';
import 'src/my_router.dart';
import 'src/server/base_info.dart';
import 'src/server/clash_routes.dart';
import 'src/server/clash_process.dart';

export 'src/server/models/models.dart';
export 'src/server/response.dart';

const version = '0.0.1';

final _router = MyRouter()
  ..get('/', (req) => .ok('Clash VPN!'))
  ..get('/version', (req) => .ok(version))
  ..mount('/baseInfo', BaseInfo.router.call)
  ..mount('/clash', ClashRoutes.handler);

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
  await ClashProcess.initialize();

  Log.defaultLogger.logPathFn = (path) => path;
  Log.defaultLogger.lines = 100;

  final handler = const Pipeline()
      .addMiddleware(jsonMiddleware)
      .addMiddleware(loggingMiddleware())
      .addHandler(_router.call);

  if (!Platform.isWindows) {
    final file = fs.currentDirectory.childFile(clashSocket);
    file.parent.createSync(recursive: true);

    if (file.existsSync()) {
      try {
        file.deleteSync();
      } on FileSystemException catch (error) {
        throw FileSystemException(
          'Failed to remove stale Clash service socket: ${error.message}',
          file.path,
          error.osError,
        );
      }
    }
  }

  if (Platform.isWindows) {
    // The service runs as LocalSystem; let local desktop users reach its API
    // named pipe while retaining SYSTEM and administrator access.
    configureWindowsServerSecurityDescriptor(
      'D:(A;;GA;;;SY)(A;;GA;;;BA)(A;;GA;;;BU)',
    );
  }
  final server = HttpServer.listenOn(await bind(clashSocket));

  io.serveRequests(server, handler, poweredByHeader: 'clash VPN');

  if (!Platform.isWindows) {
    final chmod = await Process.run('/bin/chmod', ['666', clashSocket]);
    if (chmod.exitCode != 0) {
      throw ProcessException(
        '/bin/chmod',
        ['666', clashSocket],
        '${chmod.stderr}',
        chmod.exitCode,
      );
    }
    if (!Platform.isMacOS) {
      await Process.run('chown', ['root:wheel', clashSocket]);
    }
    print('Serving at http://${server.address.host}:${server.port}');
  }
}

String get clashSocket {
  if (!Platform.isWindows) {
    return '/tmp/clashy/clash_service.sock';
  }

  return r'\\.\pipe\clashy\clash_service.pipe';
}
