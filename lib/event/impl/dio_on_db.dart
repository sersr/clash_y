import 'dart:async';
import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:path/path.dart';

import 'package:utils/utils.dart';

import '../base/events.dart';
import '../event.dart';
import '../repository.dart';
import 'clash_process.dart';
import 'clash_request.dart';
import 'db_config.dart';
import 'db_hive_base.dart';

mixin DioOnDatabaseMixin
    on HiveMixin, ClashProcessMixin, ClashRequestMixin, ConfigDatabaseMixin
    implements ConfigsEvent {
  String getBaseNameFromUrl(String url) {
    return base64.encode(utf8.encode(url));
  }

  late Box _box;

  @override
  FutureOr<bool> onClose() {
    _timer?.cancel();
    return super.onClose();
  }

  @override
  Future<void> onClashInit() async {
    _box = await Hive.openBox('_current_select_config');
    final current = _box.get('current');
    if (current != null) {
      final file = fs.currentDirectory.childFile(join(cachePath, '$current'));
      if (file.existsSync()) {
        return super.reloadConfigs(true, file.path);
      }
    }
  }

  @override
  Future<String?> getCurrentConfig() async {
    final current = _box.get('current');
    if (current is String) {
      return utf8.decode(base64Decode(current));
    }
  }

  @override
  FutureOr<void> updateCurrentConfig(String url) async {
    final current = await getCurrentConfig();
    await reloadConfigs(true, url, update: true, reload: current == url);
  }

  StreamController<ConfigsCurrent>? controller;
  @override
  Stream<ConfigsCurrent> getConfigsCurrent() {
    if (controller != null) {
      return controller!.stream;
    }
    final _controller = StreamController<ConfigsCurrent>(onCancel: () {
      controller = null;
    });
    sendConfigCurrent();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), onTimer);
    controller = _controller;
    return _controller.stream;
  }

  bool _scheduled = false;
  void sendConfigCurrent() {
    if (_scheduled) return;
    scheduleMicrotask(() async {
      final tables = await getConfigsDb();
      final current = await getCurrentConfig();
      _scheduled = false;
      if (tables != null && current != null) {
        controller?.add(ConfigsCurrent(current, tables));
      }
    });
    _scheduled = true;
  }

  Timer? _timer;
  void onTimer(t) {
    if (controller != null) {
      controller!.add(ConfigsCurrent.none);
    }
  }

  static const interval = 1000 * 60 * 60 * 24;

  @override
  FutureOr<void> reloadConfigs(bool force, String url,
      {bool update = false, bool reload = true}) async {
    return EventQueue.runOneTaskOnQueue(reloadConfigs, () async {
      try {
        final baseName = getBaseNameFromUrl(url);
        final file = fs.currentDirectory.childFile(join(cachePath, baseName));
        final fileExists = file.existsSync();
        final updateTime = await getConfigDateTime(url);

        if (!fileExists ||
            update ||
            updateTime == null ||
            updateTime is int &&
                updateTime.difference(DateTime.now()).inMilliseconds <
                    interval) {
          Log.w('update: $url', onlyDebug: false);
          final responseFile = await dio.get<String>(url);
          final fileData = responseFile.data;
          if (fileData != null) {
            final fileTemp = file.parent.childFile('$baseName.temp');
            fileTemp.writeAsStringSync(fileData);
            if (!fileExists) {
              file.createSync(recursive: true);
            }
            fileTemp.renameSync(file.path);
            await setConfigDateTime(url);
            sendConfigCurrent();
          }
        }
        final exists = file.existsSync();
        if (exists) {
          Log.w('$exists $file');
          if (reload) {
            sendConfigCurrent();
            await _box.put('current', baseName);
            await super.reloadConfigs(force, file.path);
          }
        }
      } catch (e) {
        Log.i(e);
      }
    });
  }

  Future<DateTime?> getConfigDateTime(String url) async {
    final query = db.configTable.query.updateTime..where.url.equalTo(url);
    final tables = await query.goToTable;
    if (tables.isNotEmpty) {
      return tables.last.updateTime;
    }
  }

  FutureOr<void> setConfigDateTime(String url) async {
    final query = db.configTable.update
      ..updateTime.set(DateTime.now())
      ..where.url.equalTo(url);
    await query.go;
  }
}
