import 'package:clashy/pages/home/controller/clash_controller.dart';
import 'package:clashy/pages/home/widget/home_bottom_padding.dart';
import 'package:common/common.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_nop/router.dart';

import '../../_route/routes.dart';
import 'widget/setting_item.dart';

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
              // 卸载服务只有桌面端有这回事，移动端整项隐藏。
              if (defaultTargetPlatform.isDesktop) ...[
                SettingItem(
                  label: 'Unregister service',
                  onTap: () {
                    final ClashController controller = context.getType();
                    controller.uninstall();
                  },
                ),
                const SettingDiv(),
              ],

              SettingItem(
                label: "Clash Settings",
                onTap: () => NavRoutes.clashSettings().go(),
              ),
              const SettingDiv(),

              SettingItem(
                label: "Scripts",
                onTap: () => NavRoutes.profileScriptPage().go(),
              ),
              const SettingDiv(),
              SettingItem(
                label: "WebDAV Backup",
                onTap: () => NavRoutes.webDavBackupPage().go(),
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
        body: Column(
          children: [
            appbar,
            Expanded(child: body),

            HomeBottomPadding.homePadding(context).verticalSpace,
          ],
        ),
      ),
    );
  }
}
