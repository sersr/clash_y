import 'dart:async';
import 'dart:convert';

import 'package:common/common.dart';
import 'package:dio/dio.dart';
import 'package:file/file.dart';
import 'package:hive_ce/hive.dart';
import 'package:nop/nop.dart';
import 'package:path/path.dart';

import '../event.dart';
import '../repository.dart';
import 'db_hive/db_config.dart';
import 'db_hive/db_hive_base.dart';
import 'dio/clash_request.dart';

abstract final class _BoxKey {
  static const current = 'current';
}

mixin DioOnDatabaseMixin on HiveMixin, ClashRequestMixin, ConfigDatabaseMixin
    implements ConfigsEvent {
  String getBaseNameFromUrl(String url) {
    return base64.encode(utf8.encode(url));
  }

  File getFile(String url) {
    return fs.currentDirectory.childFile(
      join(appCachePath, getBaseNameFromUrl(url)),
    );
  }

  static const _currentSelectConfig = '_current_select_config';

  IsolatedBox get _box => IsolatedHive.box(_currentSelectConfig);

  /// download config.ymal
  final dlConfigDio = Dio();

  @override
  void onResumeListen() {
    super.onResumeListen();
    onClashInit();
  }

  @override
  void initOpenBox(void Function(String name) add) {
    super.initOpenBox(add);
    add(_currentSelectConfig);
  }

  Future<void> onClashInit() async {
    final current = await _box.get(_BoxKey.current);
    if (current != null) {
      final file = getFile('$current');
      if (file.existsSync()) {
        return reloadConfigs(true, file.path);
      }
    }
  }

  @override
  Future<String?> getCurrentConfig() async {
    final current = await _box.get(_BoxKey.current);
    if (current is String) {
      return utf8.decode(base64Decode(current));
    }
    return null;
  }

  @override
  FutureOr<void> updateCurrentConfig(String url) async {
    final current = await getCurrentConfig();
    await reloadConfigs(true, url, update: true, reload: current == url);
  }

  @override
  Stream<ConfigsCurrent> getConfigsCurrent() {
    final stream = getConfigsDbStream();

    return stream.asyncMap((e) async {
      final current = await getCurrentConfig();
      return ConfigsCurrent(current ?? '', e);
    });
  }

  static const interval = 1000 * 60 * 60 * 24;

  @override
  FutureOr<void> reloadConfigs(
    bool force,
    String path, {
    bool update = false,
    bool reload = true,
  }) async {
    final url = path;
    return EventQueue.runOne(reloadConfigs, () async {
      final file = getFile(url);
      final baseName = file.basename;

      try {
        final fileExists = file.existsSync();
        final config = await getConfig(url);

        if (!fileExists || update || config?.shouldUpdate() == true) {
          Log.w('update: $url');

          final responseFile = await dlConfigDio.get<String>(
            url,
            options: .new(
              responseType: ResponseType.plain,
              headers: {'User-Agent': 'clash'},
            ),
          );
          final fileData = responseFile.data;
          if (fileData != null) {
            final editor = YamlUtils.edit(json.encode(fileData));

            updateDelegateConfig(editor);
            final fileTemp = file.parent.childFile('$baseName.temp');
            fileTemp.writeAsStringSync(editor.toString());
            if (!fileExists) {
              file.createSync(recursive: true);
            }
            fileTemp.renameSync(file.path);
            await setConfigDateTime(url);
          }
        }
        final exists = file.existsSync();
        if (exists) {
          Log.w('$exists $file');
          if (reload) {
            await _box.put(_BoxKey.current, baseName);
            await super.reloadConfigs(force, file.path);
          }
        }
      } catch (e) {
        Log.i(e);
        await super.reloadConfigs(force, file.path);
        await _box.put(_BoxKey.current, baseName);
      }
    });
  }

  Future<ConfigTable?> getConfig(String url) async {
    final query = db.configTable.query.updateTime..where.url.equalTo(url);
    final tables = await query.goToTable;

    return tables.firstOrNull;
  }

  FutureOr<void> setConfigDateTime(String url) async {
    final query = db.configTable.update
      ..updateTime.set(DateTime.now())
      ..where.url.equalTo(url);
    await query.go;
  }

  void updateDelegateConfig(YamlEditor editor) {
    editor.update([], {
      'external-controller-unix': unixSocketPath,
      'log-level': 'info',
      'mode': 'rule',
      'mixed-port': 7890,
      'allown-lan': false,
      // ipv6:
      // ntp:
      // geodata-mode:
      // geox-url:
      // geo-auto-update:
      // geo-update-interval: 24
      // rule-providers:
      //
      //
      // 'dns':
      // 'rules':
    });
  }
}
