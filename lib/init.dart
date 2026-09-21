import 'dart:async';
import 'dart:convert';

import 'package:clash_y/event/repository.dart';
import 'package:clash_y/pages/home/controller/clash_main_provider.dart';
import 'package:common/common.dart';
import 'package:flutter/foundation.dart';
import 'package:nop/nop.dart';
import 'package:yaml/yaml.dart';

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
    // ..lines = 20
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

  // mihomo binds the Unix controller socket itself. Make sure the socket's
  // parent directory exists, especially when the socket lives under the
  // application cache directory.
  if (unixSocketPath.isNotEmpty) {
    await fs.currentDirectory
        .childFile(unixSocketPath)
        .parent
        .create(recursive: true);
  }

  if (await file.exists()) {
    await compute((p) async {
      final file = fs.currentDirectory.childFile(p);
      final data =
          jsonDecode(jsonEncode(loadYaml(await file.readAsString()))) as Map;

      data['external-controller-unix'] = unixSocketPath;
      data['log-level'] = 'debug';
      data['mode'] = 'rule';
      data['ipv6'] = true;
      (data.putIfAbsent('tun', () => {}) as Map)
        ..['enable'] = true
        // ..['stack'] = 'gvisor'
        ..['stack'] = 'mixed'
        ..['device'] = 'clashy';
      data['dns'] = defaultDnsConfig();
      await file.writeAsString(YamlUtils.edit(jsonEncode(data)).toString());
      initLog();
      Log.w((jsonDecode(await file.readAsString()) as Object).logPretter);
    }, file.path);

    return configDir.path;
  }

  final configYaml = baseConfigYaml(unixSocketPath);

  await file.create(recursive: true);
  await file.writeAsString(configYaml);
  return configDir.path;
}
