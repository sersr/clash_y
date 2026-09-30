// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'package:common/common.dart';
import 'package:common/multi_window.dart' as mw;
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
    final BoxConstraints constraints = .new(minWidth: 432, minHeight: 400);
    final rect = WindowHive.windowRect.value;
    Size size;
    if (rect == .zero) {
      size = .new(432, 786);
    } else {
      size = .new(rect.rect.width, rect.rect.height);
    }

    final WindowController controller = .new(
      size: size,
      constraints: constraints,
    )..setConstraints(constraints);
    final window = controller.nativeWindow;
    if (window != null) {
      if (rect == .zero || kDebugMode) {
        if (PlatformDispatcher.instance.displays case Iterable(
          firstOrNull: var first?,
        )) {
          final sSize = first.size / first.devicePixelRatio;
          window.position = .new(x: sSize.width - size.width - 20, y: 20);
        }
      } else {
        window.position = .new(x: rect.left, y: rect.top);
      }
    }

    if (!kDebugMode) {
      late int id;
      void onEvent(mw.WindowEvent event) {
        Log.w(event);
        final w = window;
        if (w == null) return;
        if (event.windowId == w.id) {
          switch (event) {
            case mw.WindowClosedEvent():
              mw.WindowManager.instance.removeListener(id);
              break;
            case mw.WindowMovedEvent():
            case mw.WindowResizedEvent():
              final bounds = w.contentBounds;
              WindowHive.windowRect.value = .new(
                left: bounds.x,
                top: bounds.y,
                right: bounds.width + bounds.x,
                bottom: bounds.height + bounds.y,
              );
            case _:
          }
        }
      }

      id = mw.WindowManager.instance.addListener(onEvent);
    }

    return runWidget(
      WindowManager(
        initialWindows: [
          .new(
            controller: controller,
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
