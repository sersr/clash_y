// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'connections.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Connections _$ConnectionsFromJson(Map<String, dynamic> json) => Connections(
      downloadTotal: json['downloadTotal'] as int?,
      uploadTotal: json['uploadTotal'] as int?,
      connections: (json['connections'] as List<dynamic>?)
          ?.map((e) => e == null
              ? null
              : ConnectionsConnections.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$ConnectionsToJson(Connections instance) =>
    <String, dynamic>{
      'downloadTotal': instance.downloadTotal,
      'uploadTotal': instance.uploadTotal,
      'connections': instance.connections?.map((e) => e?.toJson()).toList(),
    };

ConnectionsConnections _$ConnectionsConnectionsFromJson(
        Map<String, dynamic> json) =>
    ConnectionsConnections(
      id: json['id'] as String?,
      metadata: json['metadata'] == null
          ? null
          : ConnectionsConnectionsMetadata.fromJson(
              json['metadata'] as Map<String, dynamic>),
      upload: json['upload'] as int?,
      download: json['download'] as int?,
      start: json['start'] as String?,
      chains: json['chains'] as List<dynamic>?,
      rule: json['rule'] as String?,
      rulePayload: json['rulePayload'] as String?,
    );

Map<String, dynamic> _$ConnectionsConnectionsToJson(
        ConnectionsConnections instance) =>
    <String, dynamic>{
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
        Map<String, dynamic> json) =>
    ConnectionsConnectionsMetadata(
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
        ConnectionsConnectionsMetadata instance) =>
    <String, dynamic>{
      'network': instance.network,
      'type': instance.type,
      'sourceIP': instance.sourceIP,
      'destinationIP': instance.destinationIP,
      'sourcePort': instance.sourcePort,
      'destinationPort': instance.destinationPort,
      'host': instance.host,
      'dnsMode': instance.dnsMode,
    };
