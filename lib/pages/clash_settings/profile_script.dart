import 'package:clashy/_route/routes.dart';
import 'package:clashy/pages/clash_settings/controller/profile_script_controller.dart';
import 'package:clashy/pages/clash_settings/widget/profile_script_item.dart';
import 'package:common/common.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:flutter_nop/router.dart';
import 'package:material_ui/material_ui.dart';

class ProfileScriptPage extends StatefulWidget {
  const new({super.key});

  @override
  State<ProfileScriptPage> createState() => _ProfileScriptPageState();
}

class _ProfileScriptPageState extends State<ProfileScriptPage> {
  @override
  Widget build(BuildContext context) {
    final appbar = BaseAppBar(
      leading: const BaseBackClosedButton.black(),
      center: Text(
        'Scripts',
        style: .new(color: Colors.black, fontSize: 18.sp, fontWeight: .w500),
      ),
    );

    return BaseScaffold(
      backgroundColor: const Color.fromARGB(255, 248, 248, 248),
      appbar: appbar,
      body: body.cs,
    );
  }

  late final ProfileScriptController controller = getType();

  Widget body(BuildContext context) {
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

    final scripts = controller.scripts.value;

    final body = ListView.builder(
      itemBuilder: (context, index) {
        final (:id, :data) = scripts[index];

        return ProfileScriptItem(item: data, id: id);
      },
      itemCount: scripts.length,
    );

    return Column(
      children: [
        Expanded(child: body),
        12.verticalSpace,
        Container(
          constraints: .new(maxWidth: 600),
          padding: .symmetric(horizontal: 20.w),
          child: addW,
        ),
        12.verticalSpace,
        Nav.bottomHeight.verticalSpace,
      ],
    );
  }
}
