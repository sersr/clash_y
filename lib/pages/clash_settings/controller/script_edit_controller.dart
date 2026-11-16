import 'package:common/common.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:material_ui/material_ui.dart';
import 'package:re_editor/re_editor.dart';

class ScriptEditController with AlScopeManager {
  String initText = '';
  late final name = () {
    return titleController.al.text;
  }.mount(this);

  late final CodeLineEditingController controller;
  String get scriptName => name.value.isEmpty ? 'New Script' : name.value;

  late final canPop = () {
    return name.value == _initName && !controller.al.canUndo;
  }.mount(this);

  String? id;
  String? _initName;

  late TextEditingController titleController;
  void init(ProfileScriptModel? data, String? id) {
    this.id = id;
    initText = data?.script ?? '';
    controller = .fromText(initText);
    titleController = .new(text: _initName = data?.name ?? 'New Script');
  }
}
