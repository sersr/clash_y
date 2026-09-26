import 'package:clashy/init.dart';
import 'package:common/common.dart';
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

  late IsolateManager isolateMain;

  void init() {
    isolateMain = .new()
      ..addRunner(clashMessager)
      ..addRunner(event);

    isolateMain.start();
  }

  ConfigsEvent get configsEvent => event.messageItem;
  late final event = ConfigsEventMessage.getMessage(
    .isolate(entry: _eventEntryPoint, args: paths),
  );

  late final clashMessager = ClashEventMessage.getMessage(
    .local(entry: _clashLocal, args: clashEvent),
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

ResolveRecord _clashLocal(ClashRequest clash) {
  return .new(resolves: [ClashEventMessage.getResolve(clashEvent: clash)]);
}

ResolveRecord _eventEntryPoint(Paths args) {
  initLog();

  final clash = ClashEventMessage.getResolveMessage();

  final configsEvent = EventIsolate(paths: args);

  return .new(
    resolves: [ConfigsEventMessage.getResolve(configsEvent: configsEvent)],
    messagers: [clash],
    resolveEvents: [configsEvent],
  );
}

class EventIsolate
    with ResolveEvent, DatabaseMixin, ConfigDatabaseMixin, DioOnDatabaseMixin {
  EventIsolate({required this.paths});

  @override
  final Paths paths;
}
