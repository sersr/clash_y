// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'log_model.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

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
