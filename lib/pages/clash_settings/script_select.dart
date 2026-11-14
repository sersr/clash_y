import 'package:clashy/_route/routes.dart';
import 'package:common/common.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:flutter_nop/router.dart';
import 'package:material_ui/material_ui.dart';

class ScriptSelect extends StatefulWidget {
  const new({super.key, this.current});
  final ProfileScriptModel? current;
  @override
  State<ScriptSelect> createState() => _ScriptSelectState();
}

final class _Controller with AlScopeManager {
  AV<ProfileScriptModel?> selected = .val(null);
  late final scripts = () {
    return SettingsHive.scripts.value.values.toList();
  }.mount(this);
}

class _ScriptSelectState extends State<ScriptSelect> {
  final controller = _Controller();

  @override
  void initState() {
    controller.selected.value = widget.current;
    super.initState();
  }

  @override
  void dispose() {
    controller.disposeScope();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BaseScaffold(
      backgroundColor: colors.backgroundColor,
      appbar: BaseAppBar(
        leading: const BaseBackClosedButton.black(),
        center: Text(
          "Select Script",
          style: .new(fontSize: 18.sp, color: Colors.black, fontWeight: .w500),
        ),
      ),
      body: Green.value(value: controller, child: body.cs),
    );
  }

  Widget body(BuildContext context) {
    final list = controller.scripts.value;
    final body = ListView.builder(
      itemBuilder: (context, index) {
        return _ScriptItemWidget(item: list[index]);
      },
      itemCount: list.length,
    );

    final action = InkButton(
      borderRadius: .circular(11),
      padding: .symmetric(vertical: 8.h),
      overlayColor: colors.inkOverlayColor,
      backgroundColor: colors.inkBackgroundColor,
      onPressed: () {
        final script = controller.selected.value;
        if (script != null && script.id.isNotEmpty) {
          Nav.back(script);
          return;
        }
        Nav.back();
      },
      child: Center(
        child: Text(
          'Confirm',
          style: .new(color: Colors.white, fontSize: 15.sp, fontWeight: .w500),
        ),
      ),
    );

    final addW = InkButton(
      padding: .symmetric(vertical: 8.h),
      onPressed: () {
        NavRoutes.scriptEdit(item: null, id: null).go();
      },
      overlayColor: const Color.fromARGB(44, 163, 207, 249),
      backgroundColor: const Color.fromARGB(255, 44, 122, 248),
      borderRadius: .circular(11),
      child: Center(
        child: Text(
          'Add New Script',
          style: .new(color: Colors.white, fontSize: 15.sp, fontWeight: .w500),
        ),
      ),
    );

    return Column(
      children: [
        Expanded(child: body),

        Padding(
          padding: const .all(8.0),
          child: Column(children: [addW, 12.verticalSpace, action]),
        ),
        Nav.bottomHeight.verticalSpace,
      ],
    );
  }
}

class _ScriptItemWidget extends StatelessWidget {
  const new({required this.item});
  final ProfileScriptModel item;

  @override
  Widget build(BuildContext context) {
    return body.cs;
  }

  Widget body(BuildContext context) {
    final _Controller controller = context.getType();
    final isSelected = controller.selected.value?.id == item.id;
    final nameW = Text(
      item.scriptName,
      style: .new(color: Colors.black, fontSize: 14.sp, fontWeight: .w500),
      overflow: .ellipsis,
      maxLines: 1,
    );


    final editW = GestureDetector(
      onTap: () {
        NavRoutes.scriptEdit(item: item, id: item.id).go();
      },
      child: Icon(
        Icons.edit_sharp,
        size: 22,
        color: const Color.fromARGB(255, 32, 132, 239),
      ),
    );

    final checkBox = Checkbox(
      value: isSelected,
      shape: RoundedRectangleBorder(borderRadius: .circular(3)),
      side: .new(color: Colors.blue, width: 2.r),
      checkColor: Colors.white,
      activeColor: Colors.blue,
      onChanged: (v) {
        if (v == null) return;
        if (v) {
          controller.selected.value = item;
        }
      },
    );

    Widget content = Row(
      children: [
        Expanded(child: nameW),
        12.horizontalSpace,
        editW,
        12.horizontalSpace,
        checkBox,
      ],
    );

    content = Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: .circular(8),
      ),
      padding: .symmetric(vertical: 12, horizontal: 12),
      margin: .symmetric(vertical: 5, horizontal: 12),
      child: content,
    );

    content = GestureDetector(
      onTap: () {
        controller.selected.value = item;
      },
      child: content,
    );

    return content;
  }
}
