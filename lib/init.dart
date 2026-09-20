import 'dart:async';

import 'package:clash_y/event/repository.dart';
import 'package:clash_y/pages/home/controller/clash_main_provider.dart';
import 'package:common/common.dart';
import 'package:flutter/foundation.dart';
import 'package:nop/nop.dart';

import '_route/routes.dart';
import 'pages/home/controller/clash_conections.dart';
import 'pages/home/controller/clash_configs.dart';

Future<void> initMain() async {
  try {
    initLog();
    initController();
    await [G.init()].wait;
  } catch (e) {
    Log.e("init error: $e");
  }
}

void initLog() {
  Log.defaultLogger
    ..lines = 20
    ..logPathFn = (path) => path;
}

void initController() {
  Routes.init();
  router.put(() => Repository());
  router.put(() => ClashMainNotifier());
  router.put(() => ClashConnectionsNotifier());
  router.put(() => ClashConfigNotifier());
}

Future<String> initConfigPath(String unixSocketPath) async {
  final configDir = fs.currentDirectory
      .childDirectory(G.appSubPath)
      .childDirectory('clash_config');
  final file = configDir.childFile('config.yaml');
  Log.w(file.path);

  if (await file.exists()) {
    await compute((p) async {
      final file = fs.currentDirectory.childFile(p);
      final editor = YamlUtils.edit(await file.readAsString());
      editor.update(['external-controller-unix'], unixSocketPath);
      await file.writeAsString(editor.toString());
    }, file.path);

    return configDir.path;
  }

  final configYaml = baseConfigYaml(unixSocketPath);

  await file.create(recursive: true);
  await file.writeAsString(configYaml);
  return configDir.path;
}
