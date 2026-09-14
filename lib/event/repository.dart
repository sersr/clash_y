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
  final String unixSocketPath;
  final String appConfigPath;

  const Paths({
    required this.appPath,
    required this.appConfigPath,
    required this.appSupportPath,
    required this.unixSocketPath,
  });

  factory Paths.g() {
    return Paths(
      appPath: G.appPath,
      appConfigPath: join(G.appSubPath, 'clash_config'),
      appSupportPath: G.appSubPath,
      unixSocketPath: join(G.appPath, unixSocket),
    );
  }

  @override
  String toString() {
    return '''
appPath: $appPath,
appSupportPath: $appSupportPath,
unixSockePath: $unixSocketPath,
appConfigPath: $appConfigPath,
''';
  }
}

class Repository extends MultiEventDefaultMessagerMain
    with SendCacheMixin, SendInitCloseMixin, NopLifecycle {
  static Paths? _paths;
  static Paths get paths => _paths ??= .g();

  @override
  RemoteServer get eventDefaultRemoteServer => IsolateRemoteServer(
    entryPoint: _eventEntryPoint,
    args: getArgs(_paths = Paths.g()),
  );

  @override
  void nopInit() {
    super.nopInit();
    init();
  }

  @override
  void nopDispose() {
    close();
    super.nopDispose();
  }
}

Runner _eventEntryPoint(ServerConfigurations<Paths> config) {
  initLog();
  return Runner(runner: EventIsolate(configurations: config));
}

const fs = LocalFileSystem();

class EventIsolate extends MultiEventDefaultResolveMain
    with
        DatabaseMixin,
        HiveMixin,
        ClashRequestMixin,
        ConfigDatabaseMixin,
        DioOnDatabaseMixin {
  EventIsolate({required this.configurations})
    : super(configurations: configurations);
  final ServerConfigurations<Paths> configurations;

  @override
  late final appPath = configurations.args.appPath;

  /// macos: ~/Library/com.aote.clashy
  late final appSupportPath = configurations.args.appSupportPath;

  // @override
  // String externalUi = 'http://127.0.0.1:9090/';
  // @override
  // String proxyPort = 'http://127.0.0.1:7890';

  @override
  late final unixSocketPath = configurations.args.unixSocketPath;

  @override
  late final appConfigPath = configurations.args.appConfigPath;

  @override
  void onError(message, error) {
    Log.e('$message: $error');
  }
}
