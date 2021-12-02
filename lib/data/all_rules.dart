import 'package:json_annotation/json_annotation.dart';

part 'all_rules.g.dart';

@JsonSerializable(explicitToJson: true)
class AllRules {
  const AllRules({
    this.rules,
  });
  @JsonKey(name: 'rules')
  final List<AllRulesRules?>? rules;

  factory AllRules.fromJson(Map<String,dynamic> json) => _$AllRulesFromJson(json);
  Map<String,dynamic> toJson() => _$AllRulesToJson(this);
}

@JsonSerializable(explicitToJson: true)
class AllRulesRules {
  const AllRulesRules({
    this.type,
    this.payload,
    this.proxy,
  });
  @JsonKey(name: 'type')
  final String? type;
  @JsonKey(name: 'payload')
  final String? payload;
  @JsonKey(name: 'proxy')
  final String? proxy;

  factory AllRulesRules.fromJson(Map<String,dynamic> json) => _$AllRulesRulesFromJson(json);
  Map<String,dynamic> toJson() => _$AllRulesRulesToJson(this);
}

