// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'proxy_item.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

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
