import 'dart:async';

import 'package:utils/utils.dart';
import 'package:utils/future_or_ext.dart';
import '../event.dart';
import 'db_hive_base.dart';

mixin ConfigDatabaseMixin on DatabaseMixin implements ConfigsEvent {
  String getConfigBaseName(String url) {
    final baseName = url.split('/').last.replaceAll(RegExp(r'\..*'), '');
    return baseName;
  }

  @override
  FutureOr<void> addNewConfigUrl(String url, int updateInterval, String? name) {
    final baseName = getConfigBaseName(url);
    final realName = name ?? baseName;
    assert(Log.i('baseName: $baseName'));

    final countQ = db.configTable.query
      ..select.count.all.push
      ..where.url.equalTo(url);
    return countQ.go.then((value) {
      // 如果发生错误，也会返回消息
      if (value.first.values.first == 0) {
        Log.e('....s');

        return db.configTable.insert
            .insertTable(ConfigTable(
                url: url,
                updateInterval: updateInterval,
                name: realName,
                updateTime: DateTime.now()))
            .go
            .then((insert) => Log.i('insert $realName: $insert'));
      } else {
        Log.e('....s');

        final update = db.configTable.update
          ..name.set(realName)
          ..updateInterval.set(updateInterval)
          ..where.url.equalTo(url);
        return update.go.then((update) => Log.i('update $realName: $update'));
      }
    });
  }

  void updateDateTime(String url) {
    db.configTable.update
      ..updateTime.set(DateTime.now())
      ..where.url.equalTo(url).back.whereEnd.go;
  }

  FutureOr<List<ConfigTable>?> getConfigsDb() {
    return db.configTable.query.goToTable;
  }

  @override
  FutureOr<void> removeConfigUrl(String url) {
    db.configTable.delete.where.url.equalTo(url).back.whereEnd.go;
  }

  @override
  FutureOr<void> updateConfigsUrl(String url, ConfigTable config) {
    final count = db.configTable.update..where.url.equalTo(url);
    db.configTable.updateConfigTable(count, config);
    count.go;
  }
}
