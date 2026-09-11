import 'package:common/common.dart';
import 'package:file/local.dart';
import 'package:nop/nop.dart';
import 'package:path/path.dart';

import 'base/events.dart';
import 'impl/clash_process.dart';
import 'impl/clash_request.dart';
import 'impl/db_config.dart';
import 'impl/db_hive_base.dart';
import 'impl/dio_base.dart';
import 'impl/dio_on_db.dart';

class Repository extends MultiEventDefaultMessagerMain
    with SendCacheMixin, SendInitCloseMixin {
  @override
  RemoteServer get eventDefaultRemoteServer => IsolateRemoteServer(
    entryPoint: _eventEntryPoint,
    args: getArgs(G.appPath),
  );
}

Runner _eventEntryPoint(ServerConfigurations<String> config) {
  return Runner(runner: EventIsolate(configurations: config));
}

const fs = LocalFileSystem();

class EventIsolate extends MultiEventDefaultResolveMain
    with
        DioInitMixin,
        DatabaseMixin,
        ClashProcessMixin,
        HiveMixin,
        ClashRequestMixin,
        ConfigDatabaseMixin,
        DioOnDatabaseMixin {
  EventIsolate({required this.configurations})
    : super(configurations: configurations);
  final ServerConfigurations<String> configurations;

  @override
  String get appPath => configurations.args;

  @override
  String externalUi = 'http://127.0.0.1:9090/';
  @override
  String proxyPort = 'http://127.0.0.1:7890';

  @override
  late final clashRoot = appPath;

  @override
  late final cachePath = join(clashRoot, 'caches');

  @override
  void onError(message, error) {
    Log.e('$message: $error');
  }
}
