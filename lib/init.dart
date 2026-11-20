import 'dart:async';
import 'dart:io';

import 'package:clashy/pages/application_list/controller/application_list_controller.dart';
import 'package:clashy/pages/clash_settings/controller/profile_script_controller.dart';
import 'package:clashy/pages/home/controller/clash_controller.dart';
import 'package:common/common.dart';
import 'package:common/multi_window.dart' as mw;
import 'package:flutter/services.dart';
import 'package:nop/nop.dart';

import '_route/routes.dart';
import 'event/clash_event.dart';
import 'pages/clash_settings/controller/clash_settings_controller.dart';
import 'pages/home/controller/clash_connection_controller.dart';
import 'pages/home/controller/configs_controller.dart';
import 'pages/webdav_backup/controller/webdav_backup_controller.dart';

Future<bool> initMain() async {
  try {
    initLog();
    _registerMacOsShutdownHandler();

    await [G.init()].wait;
    initController();

    return true;
  } catch (e) {
    Log.e("init error: $e");
    return false;
  }
}

void initLog() {
  Log.defaultLogger
    ..lines = 20
    ..logPathFn = (path) => path;
}

void initController() {
  Routes.init(observers: [GlobalContext.globalObserver, Overlays]);
  router.put(() => ClashController());
  router.put(() => ClashConnectionController());
  router.put(() => ConfigsController());
  router.put(() => ApplicationListController());
  router.put(() => ClashSettingsController());
  router.put(() => ProfileScriptController());
  router.put(() => WebDavBackupController());
  router.put(() => ClashEvent());
}

void _registerMacOsShutdownHandler() {
  if (!Platform.isMacOS) return;

  // 退出前先摘掉 nativeapi 的窗口事件监听，避免引擎销毁时回调崩溃。
  const MethodChannel('clashy/app').setMethodCallHandler((call) async {
    if (call.method == 'willTerminate') AppWindow.detachListeners();
  });
}

/// 主窗口的运行时状态，由 main.dart 在创建窗口时写入。
abstract final class AppWindow {
  /// nativeapi 窗口事件监听 id。
  static mw.ListenerId? listenerId;

  /// 退出前移除原生窗口事件监听。
  ///
  /// nativeapi 会在窗口关闭时把事件回调进 Dart；此时引擎已在销毁，
  /// 回调会访问失效的 isolate，导致退出时 SIGSEGV。
  static void detachListeners() {
    final id = listenerId;
    listenerId = null;
    if (id != null) mw.WindowManager.instance.removeListener(id);
  }
}
