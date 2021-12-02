import 'dart:async';

import 'package:file/local.dart';
import 'package:nop_db/nop_db.dart';
import 'package:nop_db_sqlite/nop_db_sqlite.dart';
part 'database.g.dart';

class ConfigTable extends Table {
  ConfigTable({
    this.id,
    this.name,
    this.updateInterval,
    this.updateTime,
    this.url,
  });
  @NopItem(primaryKey: true)
  String? id;
  String? url;
  String? name;
  int? updateInterval;
  DateTime? updateTime;

  @override
  Map<String, dynamic> toJson() {
    return _ConfigTable_toJson(this);
  }
}

@Nop(tables: [ConfigTable])
class ClashDatabase extends _GenClashDatabase {
  ClashDatabase._(this.path);
  int version = 1;
  final String path;
  static ClashDatabase open(String path) {
    final db = ClashDatabase._(path);
    db._open();
    return db;
  }

  void _open() {
    const fs = LocalFileSystem();
    final dbFile = fs.currentDirectory.childFile(path);
    if (!dbFile.existsSync()) {
      dbFile.createSync(recursive: true);
    }
    final db = NopDatabaseImpl.open(path,
        version: version, onCreate: onCreate, onUpgrade: onUpgrade);
    setDb(db);
  }
}
