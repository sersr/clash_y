import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:clash_window_dll/clash_window_dll.dart';
import 'package:file/local.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:nop_db/nop_db.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:utils/utils.dart';

import 'base/events.dart';
import 'impl/clash_process.dart';
import 'impl/clash_request.dart';
import 'impl/db_config.dart';
import 'impl/db_hive_base.dart';
import 'impl/dio_base.dart';
import 'impl/dio_on_db.dart';

class Repository extends EventMessagerMain
    with
        ListenMixin,
        SendEventMixin,
        SendCacheMixin,
        SendInitCloseMixin,
        SendMultiIsolateMixin,
        MultiEventDefaultMessagerMixin {
  String? appPath;
  @override
  FutureOr<void> onInitStart() async {
    final docDir = await getApplicationDocumentsDirectory();
    appPath = join(docDir.path, 'clash_y');
  }

  @override
  Future<Isolate> createIsolateEventDefault() {
    assert(appPath != null);
    return Isolate.spawn(_eventEntryPoint, [localSendPort, appPath]);
  }

  @override
  void onResumeListen() {
    super.onResumeListen();
    ClashWindowDll.setListen(_listen);
  }

  Future _listen(MethodCall call) async {
    Log.i('method: ${call.method}', onlyDebug: false);
    if (call.method == 'close') {
      await close();
    }
    if (call.method == 'getHideOnClose') {
      return false;
    }
  }

  @override
  void dispose() {
    super.dispose();
    ClashWindowDll.setListen(null);
    appPath = null;
  }
}

void _eventEntryPoint(args) {
  final remoteSendPort = args[0] as SendPort;
  final appPath = args[1] as String;
  Log.i('enter isolate');
  final event = EventIsolate(remoteSendPort: remoteSendPort, appPath: appPath);
  event.run();
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
  EventIsolate({
    required this.remoteSendPort,
    required this.appPath,
  });
  @override
  final SendPort remoteSendPort;
  @override
  final String appPath;

  @override
  String externalUi = 'http://127.0.0.1:9090/';
  @override
  String proxyPort = 'http://127.0.0.1:7890';

  // Future<void> downConfig() async {
  //   try {
  //     final response = await dio.get<String>('https://bulink.me/sub/gdxfxw/cl');
  //     final data = response.data;
  //     if (data != null) {
  //       // Log.i('data: $data');
  //       // final yaml = loadYaml(data);

  //       // Log.w(yaml);
  //       const fs = LocalFileSystem();
  //       final f =
  //           fs.currentDirectory.childDirectory(dir).childFile('config.yaml');
  //       if (!f.existsSync()) {
  //         f.createSync(recursive: true);
  //       }
  //       Log.e(f.path);
  //       await f.writeAsString(data);
  //     }
  //   } catch (e) {
  //     Log.e(e);
  //   }
  // }

  @override
  late final clashRoot = appPath;

  @override
  late final cachePath = join(clashRoot, 'caches');

  @override
  void onError(message, error) {
    Log.e('$message: $error', onlyDebug: false);
  }
}
