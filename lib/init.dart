import 'package:clash_y/event/repository.dart';
import 'package:clash_y/pages/home/controller/clash_main_provider.dart';
import 'package:common/common.dart';
import 'package:file/local.dart';
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

const fs = LocalFileSystem();

Future<String> initConfigPath() async {
  final configDir = fs.currentDirectory
      .childDirectory(G.appSubPath)
      .childDirectory('clash_config');
  final file = configDir.childFile('config.yaml');
  Log.w(file.path);

  if (await file.exists()) {
    return file.path;
  }

  final configYaml = baseConfigYaml(Repository.paths.unixSocketPath);

  await file.create(recursive: true);
  await file.writeAsString(configYaml);
  return file.path;
}
