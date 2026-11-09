import 'dart:io';

import 'response.dart';

import 'package:file/local.dart' as f;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

const fs = f.LocalFileSystem();

abstract final class BaseInfo {
  static Router get router {
    final router = Router();

    router
      ..get('/path', _getPath)
      ..get('/env', _getEnv);

    return router;
  }

  static Resp _getEnv(Request request) {
    return .ok(Platform.environment);
  }

  static Resp _getPath(Request request) {
    return .ok(Platform.resolvedExecutable);
  }
}
