// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'history.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

History _$HistoryFromJson(Map<String, dynamic> json) => History(
      history: (json['history'] as List<dynamic>?)
          ?.map((e) => e == null
              ? null
              : HistoryHistory.fromJson(e as Map<String, dynamic>))
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
      delay: json['delay'] as int?,
    );

Map<String, dynamic> _$HistoryHistoryToJson(HistoryHistory instance) =>
    <String, dynamic>{
      'time': instance.time,
      'delay': instance.delay,
    };
