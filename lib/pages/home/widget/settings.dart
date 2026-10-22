import 'package:common/common.dart';
import 'package:flutter/material.dart';

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
      children: [
        SettingDecoration(
          child: Column(
            children: [
              SettingItem(
                label: 'application list',
                onTap: () => NavRoutes.applicationList().go(),
              ),
            ],
          ),
        ),
      ],
    );

    return SystemUI(
      child: Scaffold(backgroundColor: const Color(0xFFF0F0F0), body: body),
    );
  }
}
