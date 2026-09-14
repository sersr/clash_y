import 'package:json_annotation/json_annotation.dart';

part 'log_model.g.dart';

@JsonSerializable(explicitToJson: true)
class LogModel {
  const LogModel({this.type = '', this.payload = ''});
  final String type;
  final String payload;
  factory LogModel.fromJson(Map<String, dynamic> json) =>
      _$LogModelFromJson(json);
  Map<String, dynamic> toJson() => _$LogModelToJson(this);
}

@JsonSerializable(explicitToJson: true)
class TrafficModel {
  const TrafficModel({
    this.up = 0,
    this.down = 0,
    this.upTotal = 0,
    this.downTotal = 0,
  });
  final int up;
  final int down;
  final int upTotal;
  final int downTotal;
  factory TrafficModel.fromJson(Map<String, dynamic> json) =>
      _$TrafficModelFromJson(json);
  Map<String, dynamic> toJson() => _$TrafficModelToJson(this);
}
