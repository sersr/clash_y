import 'package:common/common.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:path/path.dart';

import 'impl/dio/clash_request.dart';

final class Paths {
  final String appPath;
  final String appSupportPath;
  final String appConfigPath;

  const Paths({
    required this.appPath,
    required this.appConfigPath,
    required this.appSupportPath,
  });

  factory Paths.g() {
    return Paths(
      appPath: G.appPath,
      appConfigPath: join(G.appSubPath, 'clash_config'),
      appSupportPath: G.appSubPath,
    );
  }

  @override
  String toString() {
    return '''
appPath: $appPath,
appSupportPath: $appSupportPath,
appConfigPath: $appConfigPath,
''';
  }
}

class Repository with NopLifecycle {
  static Paths? _paths;
  static Paths get paths => _paths ??= .g();

  late final ClashRequest clashEvent = .new(paths: paths, repo: this);
  Future<void> closeConnection(String id) => clashEvent.closeConnection(id);
}
