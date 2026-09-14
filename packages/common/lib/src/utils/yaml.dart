import 'package:yaml_edit/yaml_edit.dart';
export 'package:yaml_edit/yaml_edit.dart' show YamlEditor;

abstract final class YamlUtils {
  static YamlEditor edit(String text) {
    return YamlEditor(text);
  }
}
