import 'package:clash_y/init.dart';
import 'package:common/common.dart';
import 'package:file/local.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:nop/nop.dart';
import 'package:path/path.dart';

import 'base/events.dart';
import 'impl/db_hive/db_config.dart';
import 'impl/db_hive/db_hive_base.dart';
import 'impl/dio/clash_request.dart';
import 'impl/dio_on_db.dart';

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

  late final IsolateManager isolateMain = .new()..addRunner(event);

  void init() {
    isolateMain.start();
  }

  ConfigsEvent get configsEvent => event.messageItem;
  late final event = ConfigsEventMessage.getMessage(
    IsolateRemoteServer(entryPoint: _eventEntryPoint, args: paths),
  );

  late final ClashRequest clashEvent = .new(paths: paths, repo: this);

  @override
  void nopInit() {
    init();
    super.nopInit();
  }

  void close() {
    isolateMain.dispose();
  }

  @override
  void nopDispose() {
    isolateMain.dispose();
    super.nopDispose();
  }
}

Runner _eventEntryPoint(Paths args) {
  initLog();
  final resolve = IsolateResolve();

  final isolate = EventIsolate(paths: args);
  resolve.addResolveItem(
    ConfigsEventMessage.getResolve(
      configsEvent: isolate,
      onInit: isolate.init,
      onClose: isolate.onClose,
    ),
  );

  return Runner(runner: resolve);
}

const fs = LocalFileSystem();

class EventIsolate with HiveDbMixin, ConfigDatabaseMixin, DioOnDatabaseMixin {
  EventIsolate({required this.paths});

  @override
  final Paths paths;
}
