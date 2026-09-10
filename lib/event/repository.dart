import 'dart:async';

import 'package:file/local.dart';
import 'package:nop/nop.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

import 'base/events.dart';
import 'impl/clash_process.dart';
import 'impl/clash_request.dart';
import 'impl/db_config.dart';
import 'impl/db_hive_base.dart';
import 'impl/dio_base.dart';
import 'impl/dio_on_db.dart';

class Repository extends MultiEventDefaultMessagerMain
    with SendCacheMixin, SendInitCloseMixin {
  String? appPath;
  @override
  FutureOr<void> onInitStart() async {
    final docDir = await getApplicationDocumentsDirectory();
    appPath = join(docDir.path, 'clash_y');
  }

  @override
  void dispose() {
    super.dispose();
    appPath = null;
  }

  @override
  RemoteServer get eventDefaultRemoteServer =>
      IsolateRemoteServer(entryPoint: _eventEntryPoint, args: getArgs(appPath));

  @override
  Messager get messager => this;
}

Future<Runner> _eventEntryPoint(ServerConfigurations<String?> config) async {
  final runner = EventIsolate(configurations: config, appPath: config.args!);

  return Runner(runner: runner);
  // final rec = ReceivePort();
  // Isolate.spawn(windowEntryPoint, rec.sendPort);

  // final sp = await rec.first as SendPort;
  // Timer.periodic(const Duration(seconds: 1), (timer) {
  //   sp.send('count: ${timer.tick}');
  // });
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
  EventIsolate({required this.appPath, required super.configurations});
  @override
  final String appPath;

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
