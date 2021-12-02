import 'package:json_annotation/json_annotation.dart';

part 'connections.g.dart';

@JsonSerializable(explicitToJson: true)
class Connections {
  const Connections({
    this.downloadTotal,
    this.uploadTotal,
    this.connections,
  });
  @JsonKey(name: 'downloadTotal')
  final int? downloadTotal;
  @JsonKey(name: 'uploadTotal')
  final int? uploadTotal;
  @JsonKey(name: 'connections')
  final List<ConnectionsConnections?>? connections;

  factory Connections.fromJson(Map<String,dynamic> json) => _$ConnectionsFromJson(json);
  Map<String,dynamic> toJson() => _$ConnectionsToJson(this);
}

@JsonSerializable(explicitToJson: true)
class ConnectionsConnections {
  const ConnectionsConnections({
    this.id,
    this.metadata,
    this.upload,
    this.download,
    this.start,
    this.chains,
    this.rule,
    this.rulePayload,
  });
  @JsonKey(name: 'id')
  final String? id;
  @JsonKey(name: 'metadata')
  final ConnectionsConnectionsMetadata? metadata;
  @JsonKey(name: 'upload')
  final int? upload;
  @JsonKey(name: 'download')
  final int? download;
  @JsonKey(name: 'start')
  final String? start;
  @JsonKey(name: 'chains')
  final List<dynamic>? chains;
  @JsonKey(name: 'rule')
  final String? rule;
  @JsonKey(name: 'rulePayload')
  final String? rulePayload;

  factory ConnectionsConnections.fromJson(Map<String,dynamic> json) => _$ConnectionsConnectionsFromJson(json);
  Map<String,dynamic> toJson() => _$ConnectionsConnectionsToJson(this);
}

@JsonSerializable(explicitToJson: true)
class ConnectionsConnectionsMetadata {
  const ConnectionsConnectionsMetadata({
    this.network,
    this.type,
    this.sourceIP,
    this.destinationIP,
    this.sourcePort,
    this.destinationPort,
    this.host,
    this.dnsMode,
  });
  @JsonKey(name: 'network')
  final String? network;
  @JsonKey(name: 'type')
  final String? type;
  @JsonKey(name: 'sourceIP')
  final String? sourceIP;
  @JsonKey(name: 'destinationIP')
  final String? destinationIP;
  @JsonKey(name: 'sourcePort')
  final String? sourcePort;
  @JsonKey(name: 'destinationPort')
  final String? destinationPort;
  @JsonKey(name: 'host')
  final String? host;
  @JsonKey(name: 'dnsMode')
  final String? dnsMode;

  factory ConnectionsConnectionsMetadata.fromJson(Map<String,dynamic> json) => _$ConnectionsConnectionsMetadataFromJson(json);
  Map<String,dynamic> toJson() => _$ConnectionsConnectionsMetadataToJson(this);
}

