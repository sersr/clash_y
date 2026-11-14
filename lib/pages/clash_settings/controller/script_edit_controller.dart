import 'package:code_forge/code_forge/controller.dart';
import 'package:code_forge/code_forge/undo_redo.dart';
import 'package:common/common.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:material_ui/material_ui.dart';

class ScriptEditController with AlScopeManager {
  String initText = '';
  late final name = () {
    return titleController.al.value.text;
  }.mount(this);

  final controller = CodeForgeController();
  final undoController = UndoRedoController();
  String get scriptName => name.value.isEmpty ? 'New Script' : name.value;
  late final canPop = () {
    return name.value == _initName && !undoController.al.value.canUndo;
  }.mount(this);

  String? id;
  String? _initName;

  late TextEditingController titleController;
  void init(ProfileScriptModel? data, String? id) {
    this.id = id;
    initText = data?.script ?? '';
    titleController = .new(text: _initName = data?.name ?? 'New Script');
  }
}
