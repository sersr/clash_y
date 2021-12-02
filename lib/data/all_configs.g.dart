// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'all_configs.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AllConfigs _$AllConfigsFromJson(Map<String, dynamic> json) => AllConfigs(
      port: json['port'] as int?,
      socksPort: json['socks-port'] as int?,
      redirPort: json['redir-port'] as int?,
      tproxyPort: json['tproxy-port'] as int?,
      mixedPort: json['mixed-port'] as int?,
      authentication: json['authentication'] as List<dynamic>?,
      allowLan: json['allow-lan'] as bool?,
      bindAddress: json['bind-address'] as String?,
      mode: json['mode'] as String?,
      logLevel: json['log-level'] as String?,
      ipv6: json['ipv6'] as bool?,
    );

Map<String, dynamic> _$AllConfigsToJson(AllConfigs instance) =>
    <String, dynamic>{
      'port': instance.port,
      'socks-port': instance.socksPort,
      'redir-port': instance.redirPort,
      'tproxy-port': instance.tproxyPort,
      'mixed-port': instance.mixedPort,
      'authentication': instance.authentication,
      'allow-lan': instance.allowLan,
      'bind-address': instance.bindAddress,
      'mode': instance.mode,
      'log-level': instance.logLevel,
      'ipv6': instance.ipv6,
    };
