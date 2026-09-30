// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'package:common/common.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nop/utils.dart';

import 'init.dart';
import 'pages/app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  requestNotification();

  if (!await initMain()) {
    Log.e("init failed.");
    return;
  }

  if (defaultTargetPlatform.isDesktop) {
    final constraints = BoxConstraints(minWidth: 432, minHeight: 400);
    return runWidget(
      WindowManager(
        initialWindows: [
          .new(
            controller: WindowController(
              size: .new(432, 786),
              constraints: constraints,
            )..setConstraints(constraints),
            builder: (context) {
              return const ClashApp();
            },
          ),
        ],
      ),
    );
  }

  runApp(const ClashApp());
}

extension on TargetPlatform {
  bool get isDesktop {
    return switch (this) {
      TargetPlatform.android ||
      TargetPlatform.fuchsia ||
      TargetPlatform.iOS => false,
      TargetPlatform.linux ||
      TargetPlatform.macOS ||
      TargetPlatform.windows => true,
    };
  }
}
