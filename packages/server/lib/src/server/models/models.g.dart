// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ClashStartReq _$ClashStartReqFromJson(Map<String, dynamic> json) =>
    ClashStartReq(
      args:
          (json['args'] as List<dynamic>?)?.map((e) => e as String).toList() ??
          const [],
    );

Map<String, dynamic> _$ClashStartReqToJson(ClashStartReq instance) =>
    <String, dynamic>{'args': instance.args};
