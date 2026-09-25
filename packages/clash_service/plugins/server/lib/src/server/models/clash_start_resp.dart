part of 'models.dart';

@JsonSerializable(explicitToJson: true)
class ClashStartReq {
  const ClashStartReq({this.args = const []});
  final List<String> args;
  factory ClashStartReq.fromJson(Map<String, dynamic> json) =>
      _$ClashStartReqFromJson(json);
  Map<String, dynamic> toJson() => _$ClashStartReqToJson(this);
}
