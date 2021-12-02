import 'package:json_annotation/json_annotation.dart';

part 'traffic.g.dart';

@JsonSerializable(explicitToJson: true)
class Traffic {
  const Traffic({
    this.up,
    this.down,
  });
  @JsonKey(name: 'up')
  final int? up;
  @JsonKey(name: 'down')
  final int? down;

  factory Traffic.fromJson(Map<String,dynamic> json) => _$TrafficFromJson(json);
  Map<String,dynamic> toJson() => _$TrafficToJson(this);
}

