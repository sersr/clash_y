// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// **************************************************************************
// Generator: GenNopGeneratorForAnnotation
// **************************************************************************

// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: non_constant_identifier_names

abstract class _GenClashDatabase extends $Database {
  late final _tables = <DatabaseTable>[configTable];

  @override
  List<DatabaseTable> get tables => _tables;

  late final configTable = GenConfigTable(this);
}

Map<String, dynamic> _ConfigTable_toJson(ConfigTable table) {
  return {
    'id': table.id,
    'url': table.url,
    'name': table.name,
    'updateInterval': table.updateInterval,
    'updateTime': table.updateTime,
    'upload': table.upload,
    'download': table.download,
    'total': table.total,
    'expire': table.expire,
  };
}

class GenConfigTable extends DatabaseTable<ConfigTable, GenConfigTable> {
  GenConfigTable($Database db) : super(db);

  @override
  final table = 'ConfigTable';
  final id = 'id';
  final url = 'url';
  final name = 'name';
  final updateInterval = 'updateInterval';
  final updateTime = 'updateTime';
  final upload = 'upload';
  final download = 'download';
  final total = 'total';
  final expire = 'expire';

  void updateConfigTable(
    UpdateStatement<ConfigTable, GenConfigTable> update,
    ConfigTable configTable,
  ) {
    if (configTable.id != null) update.id.set(configTable.id);

    if (configTable.url != null) update.url.set(configTable.url);

    if (configTable.name != null) update.name.set(configTable.name);

    if (configTable.updateInterval != null)
      update.updateInterval.set(configTable.updateInterval);

    if (configTable.updateTime != null)
      update.updateTime.set(configTable.updateTime);

    if (configTable.upload != null) update.upload.set(configTable.upload);

    if (configTable.download != null) update.download.set(configTable.download);

    if (configTable.total != null) update.total.set(configTable.total);

    if (configTable.expire != null) update.expire.set(configTable.expire);
  }

  @override
  String createTable() {
    return 'CREATE TABLE IF NOT EXISTS $table ($id TEXT PRIMARY KEY, $url TEXT, '
        '$name TEXT, $updateInterval INTEGER, $updateTime TEXT, $upload INTEGER, '
        '$download INTEGER, $total INTEGER, $expire INTEGER)';
  }

  static ConfigTable mapToTable(Map<String, dynamic> map) => ConfigTable(
    id: map['id'] as String?,
    url: map['url'] as String?,
    name: map['name'] as String?,
    updateInterval: map['updateInterval'] as int?,
    updateTime: DateTime.tryParse(map['updateTime'] as String? ?? ''),
    upload: map['upload'] as int?,
    download: map['download'] as int?,
    total: map['total'] as int?,
    expire: map['expire'] as int?,
  );

  @override
  List<ConfigTable> toTable(Iterable<Map<String, Object?>> query) =>
      query.map((e) => mapToTable(e)).toList();
}

extension ItemExtensionConfigTable<T extends ItemExtension<GenConfigTable>>
    on T {
  T get id => item(table.id) as T;

  T get url => item(table.url) as T;

  T get name => item(table.name) as T;

  T get updateInterval => item(table.updateInterval) as T;

  T get updateTime => item(table.updateTime) as T;

  T get upload => item(table.upload) as T;

  T get download => item(table.download) as T;

  T get total => item(table.total) as T;

  T get expire => item(table.expire) as T;

  T get configTable_id => id;

  T get configTable_url => url;

  T get configTable_name => name;

  T get configTable_updateInterval => updateInterval;

  T get configTable_updateTime => updateTime;

  T get configTable_upload => upload;

  T get configTable_download => download;

  T get configTable_total => total;

  T get configTable_expire => expire;
}

extension JoinItemConfigTable<J extends JoinItem<GenConfigTable>> on J {
  J get configTable_id => joinItem(joinTable.id) as J;

  J get configTable_url => joinItem(joinTable.url) as J;

  J get configTable_name => joinItem(joinTable.name) as J;

  J get configTable_updateInterval => joinItem(joinTable.updateInterval) as J;

  J get configTable_updateTime => joinItem(joinTable.updateTime) as J;

  J get configTable_upload => joinItem(joinTable.upload) as J;

  J get configTable_download => joinItem(joinTable.download) as J;

  J get configTable_total => joinItem(joinTable.total) as J;

  J get configTable_expire => joinItem(joinTable.expire) as J;
}
