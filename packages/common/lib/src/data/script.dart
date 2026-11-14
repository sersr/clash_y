part of '_g.dart';

@JsonSerializable(explicitToJson: true)
class ProfileScriptModel {
  const ProfileScriptModel({this.script = '', this.name = '', required this.id});
  final String script;
  final String name;
  final String id;

  String? get idOrNull {
    if (id.isEmpty) return null;
    return id;
  }
  String get scriptName {
    if (name.isNotEmpty) return name;
    return LineSplitter.split(script).firstOrNull ?? '';
  }

  factory ProfileScriptModel.fromJson(Map<String, dynamic> json) =>
      _$ProfileScriptModelFromJson(json);
  Map<String, dynamic> toJson() => _$ProfileScriptModelToJson(this);
}
