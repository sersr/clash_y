// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'all_rules.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AllRules _$AllRulesFromJson(Map<String, dynamic> json) => AllRules(
      rules: (json['rules'] as List<dynamic>?)
          ?.map((e) => e == null
              ? null
              : AllRulesRules.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$AllRulesToJson(AllRules instance) => <String, dynamic>{
      'rules': instance.rules?.map((e) => e?.toJson()).toList(),
    };

AllRulesRules _$AllRulesRulesFromJson(Map<String, dynamic> json) =>
    AllRulesRules(
      type: json['type'] as String?,
      payload: json['payload'] as String?,
      proxy: json['proxy'] as String?,
    );

Map<String, dynamic> _$AllRulesRulesToJson(AllRulesRules instance) =>
    <String, dynamic>{
      'type': instance.type,
      'payload': instance.payload,
      'proxy': instance.proxy,
    };
