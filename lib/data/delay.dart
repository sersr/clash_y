import 'package:json_annotation/json_annotation.dart';

part 'delay.g.dart';

@JsonSerializable(explicitToJson: true)
class Delay {
  const Delay({
    this.delay,
  });
  @JsonKey(name: 'delay')
  final int? delay;

  factory Delay.fromJson(Map<String,dynamic> json) => _$DelayFromJson(json);
  Map<String,dynamic> toJson() => _$DelayToJson(this);
}

