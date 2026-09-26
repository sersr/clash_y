import 'package:common/common.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart';

abstract final class HiveBoxKey {
  static const config = 'config';
}

abstract final class Hives {
  static Box get config => Hive.box(HiveBoxKey.config);

  static Future<void> init(String path) {
    Hive.init(path);
    return [Hive.openBox(HiveBoxKey.config)].wait;
  }
}

abstract final class _BoxKey {
  static const current = 'currentProfile';
  static const baseConfig = 'baseConfig';
  static const unixSockPath = 'unixSockPath';
}

abstract final class BaseConfig {
  static final AV<String?> currentProfile = Hives.config.read(_BoxKey.current);

  static final AV<String> unixSockPath = Hives.config.readDefault(
    _BoxKey.unixSockPath,
    join(G.appCachePath, 'clash_config', 'socket_clash.sock'),
  );

  static final AV<MihomoRootConfig> baseConfig = Hives.config.readDefault(
    _BoxKey.baseConfig,
    MihomoRootConfig(externalController: unixSockPath.value),
  );
}
