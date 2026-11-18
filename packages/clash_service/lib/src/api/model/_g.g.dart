// GENERATED CODE - DO NOT MODIFY BY HAND

part of '_g.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Connections _$ConnectionsFromJson(Map<String, dynamic> json) => Connections(
  downloadTotal: (json['downloadTotal'] as num?)?.toInt(),
  uploadTotal: (json['uploadTotal'] as num?)?.toInt(),
  connections: (json['connections'] as List<dynamic>?)
      ?.map(
        (e) => e == null
            ? null
            : ConnectionsConnections.fromJson(e as Map<String, dynamic>),
      )
      .toList(),
);

Map<String, dynamic> _$ConnectionsToJson(Connections instance) =>
    <String, dynamic>{
      'downloadTotal': instance.downloadTotal,
      'uploadTotal': instance.uploadTotal,
      'connections': instance.connections?.map((e) => e?.toJson()).toList(),
    };

ConnectionsConnections _$ConnectionsConnectionsFromJson(
  Map<String, dynamic> json,
) => ConnectionsConnections(
  id: json['id'] as String?,
  metadata: json['metadata'] == null
      ? null
      : ConnectionsConnectionsMetadata.fromJson(
          json['metadata'] as Map<String, dynamic>,
        ),
  upload: (json['upload'] as num?)?.toInt(),
  download: (json['download'] as num?)?.toInt(),
  start: json['start'] as String?,
  chains: json['chains'] as List<dynamic>?,
  rule: json['rule'] as String?,
  rulePayload: json['rulePayload'] as String?,
);

Map<String, dynamic> _$ConnectionsConnectionsToJson(
  ConnectionsConnections instance,
) => <String, dynamic>{
  'id': instance.id,
  'metadata': instance.metadata?.toJson(),
  'upload': instance.upload,
  'download': instance.download,
  'start': instance.start,
  'chains': instance.chains,
  'rule': instance.rule,
  'rulePayload': instance.rulePayload,
};

ConnectionsConnectionsMetadata _$ConnectionsConnectionsMetadataFromJson(
  Map<String, dynamic> json,
) => ConnectionsConnectionsMetadata(
  network: json['network'] as String?,
  type: json['type'] as String?,
  sourceIP: json['sourceIP'] as String?,
  destinationIP: json['destinationIP'] as String?,
  sourcePort: json['sourcePort'] as String?,
  destinationPort: json['destinationPort'] as String?,
  host: json['host'] as String?,
  dnsMode: json['dnsMode'] as String?,
);

Map<String, dynamic> _$ConnectionsConnectionsMetadataToJson(
  ConnectionsConnectionsMetadata instance,
) => <String, dynamic>{
  'network': instance.network,
  'type': instance.type,
  'sourceIP': instance.sourceIP,
  'destinationIP': instance.destinationIP,
  'sourcePort': instance.sourcePort,
  'destinationPort': instance.destinationPort,
  'host': instance.host,
  'dnsMode': instance.dnsMode,
};

Delay _$DelayFromJson(Map<String, dynamic> json) =>
    Delay(delay: (json['delay'] as num?)?.toInt());

Map<String, dynamic> _$DelayToJson(Delay instance) => <String, dynamic>{
  'delay': instance.delay,
};

History _$HistoryFromJson(Map<String, dynamic> json) => History(
  history: (json['history'] as List<dynamic>?)
      ?.map(
        (e) => e == null
            ? null
            : HistoryHistory.fromJson(e as Map<String, dynamic>),
      )
      .toList(),
  name: json['name'] as String?,
  type: json['type'] as String?,
  udp: json['udp'] as bool?,
);

Map<String, dynamic> _$HistoryToJson(History instance) => <String, dynamic>{
  'history': instance.history?.map((e) => e?.toJson()).toList(),
  'name': instance.name,
  'type': instance.type,
  'udp': instance.udp,
};

HistoryHistory _$HistoryHistoryFromJson(Map<String, dynamic> json) =>
    HistoryHistory(
      time: json['time'] as String?,
      delay: (json['delay'] as num?)?.toInt(),
    );

Map<String, dynamic> _$HistoryHistoryToJson(HistoryHistory instance) =>
    <String, dynamic>{'time': instance.time, 'delay': instance.delay};

Profile _$ProfileFromJson(Map<String, dynamic> json) => Profile(
  id: json['id'] as String?,
  name: json['name'] as String?,
  rawName: json['rawName'] as String?,
  updateInterval: (json['updateInterval'] as num?)?.toInt(),
  updateTime: json['updateTime'] == null
      ? null
      : DateTime.parse(json['updateTime'] as String),
  url: json['url'] as String?,
  upload: (json['upload'] as num?)?.toInt(),
  download: (json['download'] as num?)?.toInt(),
  total: (json['total'] as num?)?.toInt(),
  expire: (json['expire'] as num?)?.toInt(),
  scriptId: json['scriptId'] as String?,
  isError: json['isError'] as bool?,
);

Map<String, dynamic> _$ProfileToJson(Profile instance) => <String, dynamic>{
  'id': instance.id,
  'url': instance.url,
  'name': instance.name,
  'rawName': instance.rawName,
  'updateInterval': instance.updateInterval,
  'updateTime': instance.updateTime?.toIso8601String(),
  'scriptId': instance.scriptId,
  'upload': instance.upload,
  'download': instance.download,
  'total': instance.total,
  'expire': instance.expire,
  'isError': instance.isError,
};

ProxyItem _$ProxyItemFromJson(Map<String, dynamic> json) => ProxyItem(
  all: json['all'] as List<dynamic>?,
  history: json['history'] as List<dynamic>?,
  name: json['name'] as String?,
  now: json['now'] as String?,
  type: json['type'] as String?,
  udp: json['udp'] as bool?,
);

Map<String, dynamic> _$ProxyItemToJson(ProxyItem instance) => <String, dynamic>{
  'all': instance.all,
  'history': instance.history,
  'name': instance.name,
  'now': instance.now,
  'type': instance.type,
  'udp': instance.udp,
};

LogModel _$LogModelFromJson(Map<String, dynamic> json) => LogModel(
  type: json['type'] as String? ?? '',
  payload: json['payload'] as String? ?? '',
);

Map<String, dynamic> _$LogModelToJson(LogModel instance) => <String, dynamic>{
  'type': instance.type,
  'payload': instance.payload,
};

TrafficModel _$TrafficModelFromJson(Map<String, dynamic> json) => TrafficModel(
  up: (json['up'] as num?)?.toInt() ?? 0,
  down: (json['down'] as num?)?.toInt() ?? 0,
  upTotal: (json['upTotal'] as num?)?.toInt() ?? 0,
  downTotal: (json['downTotal'] as num?)?.toInt() ?? 0,
);

Map<String, dynamic> _$TrafficModelToJson(TrafficModel instance) =>
    <String, dynamic>{
      'up': instance.up,
      'down': instance.down,
      'upTotal': instance.upTotal,
      'downTotal': instance.downTotal,
    };
