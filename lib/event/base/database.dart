import 'package:file/local.dart';
import 'package:nop/nop.dart';
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
    this.upload,
    this.download,
    this.total,
    this.expire,
  });
  @NopDbItem(primaryKey: true)
  String? id;
  String? url;
  String? name;
  int? updateInterval;
  DateTime? updateTime;

  // subscription-userinfo
  final int? upload;
  final int? download;
  final int? total;
  final int? expire;

  bool shouldUpdate() {
    final lastUpdateTime = updateTime;
    if (lastUpdateTime == null) return true;
    final interval = updateInterval;
    if (interval == null) return true;

    return DateTime.now().difference(lastUpdateTime).inMinutes >= interval;
  }

  @override
  Map<String, dynamic> toJson() {
    return _ConfigTable_toJson(this);
  }
}

@NopDb(tables: [ConfigTable])
class ClashDatabase extends _GenClashDatabase {
  ClashDatabase._(this.path);
  int version = 2;
  final String path;
  static ClashDatabase open(String path) {
    final db = ClashDatabase._(path);
    db._open();
    return db;
  }

  void _open() async {
    const fs = LocalFileSystem();
    final dbFile = fs.currentDirectory.childFile(path);
    if (!dbFile.existsSync()) {
      dbFile.createSync(recursive: true);
    }
    final db = NopDatabaseImpl.open(
      path,
      version: version,
      onCreate: onCreate,
      onUpgrade: onUpgrade,
    );
    setDb(db);
  }

  @override
  void onUpgrade(NopDatabase db, int oldVersion, int newVersion) {
    if (oldVersion <= 1) {
      try {
        final indexTable = configTable.table;
        db.execute(
          'ALTER TABLE $indexTable ADD COLUMN ${configTable.upload} INTEGER',
        );
        db.execute(
          'ALTER TABLE $indexTable ADD COLUMN ${configTable.download} INTEGER',
        );
        db.execute(
          'ALTER TABLE $indexTable ADD COLUMN ${configTable.total} INTEGER',
        );
        db.execute(
          'ALTER TABLE $indexTable ADD COLUMN ${configTable.expire} INTEGER',
        );
      } catch (e) {
        Log.i('error: $e');
      }
    }
  }
}
