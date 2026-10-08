import 'package:common/common.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart';

enum Hives with StorageMixin, StorageMixinEnumBox, StorageMixinHive {
  config,
  window;

  static Iterable<Future<Box>> _openAll() =>
      values.map((e) => Hive.openBox(e.name));

  static Future<void> init(String path) {
    Hive.init(path);
    return _openAll().wait;
  }
}

enum ConfigKey { currentProfile, baseConfig, unixSockPath }

abstract final class BaseConfig {
  static final currentProfile = Hives.config.read(
    ConfigKey.currentProfile,
    .string(),
  );

  static final unixSockPath = Hives.config.readDef(
    ConfigKey.unixSockPath,
    .string(join(G.appCachePath, 'clash_config', 'socket_clash.sock')),
  );

  static final baseConfig = Hives.config.readDef(
    ConfigKey.baseConfig,
    .fromJson(
      MihomoRootConfig.fromJson,
      MihomoRootConfig(externalController: unixSockPath.value),
    ),
  );
}

enum _Window { windowRect }

abstract final class WindowHive {
  static final windowRect = Hives.window.readDef(
    _Window.windowRect,
    .fromJson(WindowRect.fromJson, WindowRect.zero),
  );
}
