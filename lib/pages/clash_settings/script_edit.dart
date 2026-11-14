import 'package:clashy/pages/clash_settings/controller/profile_script_controller.dart';
import 'package:clashy/pages/clash_settings/controller/script_edit_controller.dart';
import 'package:code_forge/code_forge.dart';
import 'package:common/common.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:flutter_nop/router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:re_highlight/languages/javascript.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:uuid/uuid.dart';

class ScriptEdit extends StatefulWidget {
  const new({super.key, required this.item, required this.id});
  final ProfileScriptModel? item;
  final String? id;
  @override
  State<ScriptEdit> createState() => _ScriptEditState();
}

class _ScriptEditState extends State<ScriptEdit> {
  final controller = ScriptEditController();
  late final scriptController = getType<ProfileScriptController>();
  @override
  void initState() {
    controller.init(widget.item, widget.id);
    super.initState();
  }

  @override
  void dispose() {
    controller.disposeScope();
    super.dispose();
  }

  void save() {
    // controller.verify();

    final id = controller.id ?? Uuid().v4();
    SettingsHive.scripts.al.al[id] = .new(
      id: id,
      script: controller.controller.text,
      name: controller.scriptName,
    );
    Nav.back();
  }

  @override
  Widget build(BuildContext context) {
    final saveW = IntrinsicWidth(
      child: Center(
        child: Padding(
          padding: .only(left: 10.w),
          child: InkButton(
            backgroundColor: const Color.fromARGB(255, 238, 237, 237),
            overlayColor: const Color.fromARGB(74, 198, 198, 198),
            isStadium: true,
            padding: .symmetric(horizontal: 12, vertical: 5),
            onPressed: save,
            child: Text(
              'Save',
              style: .new(
                color: const Color.fromARGB(255, 117, 116, 116),
                fontSize: 13.sp,
                fontWeight: .w500,
              ),
            ),
          ),
        ),
      ),
    );
    return BaseScaffold(
      backgroundColor: colors.backgroundColor,
      appbar: SafeArea(
        bottom: false,
        child: Cs(() {
          return TextField(
            controller: controller.titleController,
            style: .new(
              color: Colors.black,
              fontWeight: .w500,
              fontSize: 18.sp,
            ),
            textAlignVertical: .center,
            decoration: .new(
              isCollapsed: true,
              border: .none,
              contentPadding: .symmetric(vertical: 12),
              prefixIconConstraints: .new(minHeight: 50.h),
              constraints: .new(minHeight: 50.h),
              isDense: true,
              prefixIcon: Padding(
                padding: .only(right: 10),
                child: Cs(() {
                  return PopScope(
                    canPop: controller.canPop.value,
                    onPopInvokedWithResult: (didPop, result) {
                      if (didPop) return;
                      _saveDialog(controller.name.value);
                    },
                    child: controller.canPop.value
                        ? const BaseBackClosedButton.black()
                        : saveW,
                  );
                }),
              ),
              suffixIcon: TextClearSufWidget(
                controller: controller.titleController,
              ),
            ),
          );
        }),
      ),
      body: _build.cs,
    );
  }

  Widget _build(BuildContext context) {
    return CodeForge(
      language: langJavascript,
      initialText: controller.initText,
      controller: controller.controller,
      undoController: controller.undoController,
      editorTheme: atomOneDarkTheme,
    );
  }
}

Future<bool?> _saveDialog(String name) async {
  final res = await showCenterDialog(currentContext, _SaveDialog(name: name));
  if (res is bool) return res;
  return null;
}

class _SaveDialog extends StatefulWidget {
  const new({required this.name});
  final String name;

  @override
  State<_SaveDialog> createState() => _SaveDialogState();
}

class _SaveDialogState extends State<_SaveDialog> {
  @override
  Widget build(BuildContext context) {
    final name = widget.name.isEmpty ? 'New Script' : widget.name;
    final titleW = BaseAppBar(
      removeTop: false,
      center: Text(
        'Save [$name]?',
        style: .new(color: Colors.black, fontSize: 15.sp, fontWeight: .w500),
      ),
    );

    final content = Text(
      'You have unsaved changes. If you exit now, your changes will be lost. Are you sure you want to exit?',
      textAlign: .center,
      style: .new(
        color: Color.fromARGB(255, 118, 116, 116),
        fontSize: 13.sp,
        fontWeight: .w400,
      ),
    );

    final cancelW = InkButton(
      backgroundColor: Colors.transparent,
      padding: .symmetric(vertical: 14),
      overlayColor: const Color.fromARGB(41, 166, 166, 166),
      borderRadius: .zero,
      onPressed: () {
        Nav.back(false);
      },
      child: Center(
        child: Text(
          'Cancel',
          style: .new(
            color: const Color.fromARGB(255, 139, 139, 139),
            fontSize: 14.sp,
            fontWeight: .w400,
          ),
        ),
      ),
    );

    final saveW = InkButton(
      backgroundColor: Colors.transparent,
      padding: .symmetric(vertical: 14),
      overlayColor: const Color.fromARGB(52, 96, 147, 248),
      borderRadius: .zero,
      onPressed: () {
        Nav.back(true);
      },
      child: Center(
        child: Text(
          'Save',
          style: .new(
            color: const Color.fromARGB(255, 43, 126, 244),
            fontSize: 14.sp,
            fontWeight: .w400,
          ),
        ),
      ),
    );

    Widget body = Column(
      mainAxisSize: .min,
      children: [titleW, 12.verticalSpace, content, 32.verticalSpace],
    );

    body = Container(
      padding: .symmetric(horizontal: 20.w, vertical: 20.h),
      child: body,
    );

    body = Column(
      mainAxisSize: .min,
      children: [
        body,

        Container(
          color: const Color.fromARGB(108, 213, 213, 213),
          height: 0.5.r,
          width: double.infinity,
        ),

        IntrinsicHeight(
          child: Row(
            children: [
              Expanded(child: cancelW),
              Container(
                color: const Color.fromARGB(108, 213, 213, 213),
                width: 0.5.r,
              ),
              Expanded(child: saveW),
            ],
          ),
        ),
      ],
    );

    body = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: .circular(20),
      ),
      clipBehavior: .hardEdge,
      margin: .symmetric(horizontal: 24.w),
      child: body,
    );
    body = Material(color: Colors.transparent, child: body);

    return body;
  }
}
