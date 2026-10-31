import 'dart:async';
import 'dart:io';

import 'package:clashy/app_window.dart';
import 'package:clashy/event/repository.dart';
import 'package:clashy/pages/application_list/controller/application_list_controller.dart';
import 'package:clashy/pages/home/controller/clash_controller.dart';
import 'package:common/common.dart';
import 'package:flutter/services.dart';
import 'package:nop/nop.dart';

import '_route/routes.dart';
import 'pages/home/controller/clash_connection_controller.dart';
import 'pages/home/controller/configs_controller.dart';

Future<bool> initMain() async {
  try {
    initLog();
    initController();
    await [G.init()].wait;
    _registerMacOsShutdownHandler();
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
  Routes.init(observers: [globalObserver, Overlays]);
  router.put(() => Repository());
  router.put(() => ClashController());
  router.put(() => ClashConnectionController());
  router.put(() => ConfigsController());
  router.put(() => ApplicationListController());
}

void _registerMacOsShutdownHandler() {
  if (!Platform.isMacOS) return;

  // 退出前先摘掉 nativeapi 的窗口事件监听，避免引擎销毁时回调崩溃。
  const MethodChannel('clashy/app').setMethodCallHandler((call) async {
    if (call.method == 'willTerminate') AppWindow.detachListeners();
  });
}
