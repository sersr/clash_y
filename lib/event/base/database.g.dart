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
    'updateTime': table.updateTime
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

  void updateConfigTable(UpdateStatement<ConfigTable, GenConfigTable> update,
      ConfigTable configTable) {
    if (configTable.id != null) update.id.set(configTable.id);

    if (configTable.url != null) update.url.set(configTable.url);

    if (configTable.name != null) update.name.set(configTable.name);

    if (configTable.updateInterval != null)
      update.updateInterval.set(configTable.updateInterval);

    if (configTable.updateTime != null)
      update.updateTime.set(configTable.updateTime);
  }

  @override
  String createTable() {
    return 'CREATE TABLE $table ($id TEXT PRIMARY KEY, $url TEXT, $name TEXT, '
        '$updateInterval INTEGER, $updateTime TEXT)';
  }

  static ConfigTable mapToTable(Map<String, dynamic> map) => ConfigTable(
      id: map['id'] as String?,
      url: map['url'] as String?,
      name: map['name'] as String?,
      updateInterval: map['updateInterval'] as int?,
      updateTime: DateTime.tryParse(map['updateTime'] as String? ?? ''));

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

  T get genConfigTable_id => id;

  T get genConfigTable_url => url;

  T get genConfigTable_name => name;

  T get genConfigTable_updateInterval => updateInterval;

  T get genConfigTable_updateTime => updateTime;
}

extension JoinItemConfigTable<J extends JoinItem<GenConfigTable>> on J {
  J get genConfigTable_id => joinItem(joinTable.id) as J;

  J get genConfigTable_url => joinItem(joinTable.url) as J;

  J get genConfigTable_name => joinItem(joinTable.name) as J;

  J get genConfigTable_updateInterval =>
      joinItem(joinTable.updateInterval) as J;

  J get genConfigTable_updateTime => joinItem(joinTable.updateTime) as J;
}
