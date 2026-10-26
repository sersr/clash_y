import 'package:clashy/pages/home/controller/clash_controller.dart';
import 'package:common/common.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_nop/router.dart';

import '../../../_route/routes.dart';
import 'setting_item.dart';

class Settings extends StatefulWidget {
  const new({super.key});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  @override
  Widget build(BuildContext context) {
    final body = ListView(
      padding: .symmetric(vertical: 12.h),
      children: [
        SettingDecoration(
          child: Column(
            children: [
              SettingItem(
                label: 'Application list',
                onTap: () => NavRoutes.applicationList().go(),
              ),
              const SettingDiv(),
              SettingItem(
                label: 'Unregister service',
                onTap: () {
                  final ClashController controller = context.getType();
                  controller.uninstall();
                },
              ),
            ],
          ),
        ),
      ],
    );

    final appbar = BaseAppBar(
      center: Text(
        'Settings',
        style: .new(fontSize: 18.sp, fontWeight: .w500),
      ),
    );

    return SystemUI(
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F0F0),
        body: SafeUI(
          child: Column(
            children: [
              appbar,
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }
}
