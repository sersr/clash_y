import 'dart:async';

import '../event.dart';
import 'db_hive/db_config.dart';

mixin DioOnDatabaseMixin on ConfigDatabaseMixin implements ConfigsEvent {
  @override
  Stream<ConfigsCurrent> getConfigsCurrent() {
    final stream = getConfigsDbStream();

    return stream.map(ConfigsCurrent.new);
  }

  static const interval = 1000 * 60 * 60 * 24;

  /// database
  @override
  Future<ConfigTable?> getConfig(String url) async {
    final query = db.configTable.query..where.url.equalTo(url);
    final tables = await query.goToTable;

    return tables.firstOrNull;
  }

  @override
  FutureOr<void> setConfigDateTime(String url, String info) async {
    final list = info.split(';');
    final map = <String, dynamic>{};
    for (var item in list) {
      final pair = item.split('=');
      if (pair case [String name, String value]) {
        map[name.trim()] = int.tryParse(value);
      }
    }

    final query = db.configTable.update
      ..updateTime.set(DateTime.now())
      ..upload.set(map['upload'])
      ..download.set(map['download'])
      ..total.set(map['total'])
      ..expire.set(map['expire'])
      ..where.url.equalTo(url);
    await query.go;
  }
}
