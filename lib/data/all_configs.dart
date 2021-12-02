import 'package:json_annotation/json_annotation.dart';

part 'all_configs.g.dart';

@JsonSerializable(explicitToJson: true)
class AllConfigs {
  const AllConfigs({
    this.port,
    this.socksPort,
    this.redirPort,
    this.tproxyPort,
    this.mixedPort,
    this.authentication,
    this.allowLan,
    this.bindAddress,
    this.mode,
    this.logLevel,
    this.ipv6,
  });
  @JsonKey(name: 'port')
  final int? port;
  @JsonKey(name: 'socks-port')
  final int? socksPort;
  @JsonKey(name: 'redir-port')
  final int? redirPort;
  @JsonKey(name: 'tproxy-port')
  final int? tproxyPort;
  @JsonKey(name: 'mixed-port')
  final int? mixedPort;
  @JsonKey(name: 'authentication')
  final List<dynamic>? authentication;
  @JsonKey(name: 'allow-lan')
  final bool? allowLan;
  @JsonKey(name: 'bind-address')
  final String? bindAddress;
  @JsonKey(name: 'mode')
  final String? mode;
  @JsonKey(name: 'log-level')
  final String? logLevel;
  @JsonKey(name: 'ipv6')
  final bool? ipv6;

  factory AllConfigs.fromJson(Map<String,dynamic> json) => _$AllConfigsFromJson(json);
  Map<String,dynamic> toJson() => _$AllConfigsToJson(this);
}

