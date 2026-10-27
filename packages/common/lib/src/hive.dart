import 'package:common/common.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart';

part 'hive/settings.dart';
part 'hive/model.dart';

enum Hives with StorageMixin, StorageMixinEnumBox, StorageMixinHive {
  settings,
  config,
  window;

  static Iterable<Future<Box>> _openAll() =>
      values.map((e) => Hive.openBox(e.name));

  static Future<void> init(String path) {
    Hive.init(path);
    return _openAll().wait;
  }
}

enum ConfigKey with StorageEnum {
  currentProfile,
  profiles,
  baseConfig,
  unixSockPath;

  @override
  StorageMixin get target => Hives.config;
}

abstract final class BaseConfig {
  static final currentProfile = ConfigKey.currentProfile.readDef(
    .fromJson(Profile.fromJson, Profile()),
  );

  static final profiles = ConfigKey.profiles
      .readDef(.map(Profile.fromJson, <String, Profile>{}))
      .al;

  static final unixSockPath = ConfigKey.unixSockPath.readDef(
    .string(
      defaultTargetPlatform == .windows
          ? r"\\.\pipe\clashy.pipe"
          : join(G.appCachePath, 'clash_config', 'socket_clash.sock'),
    ),
  );

  static final baseConfig = ConfigKey.baseConfig.readDef(
    .fromJson(MihomoRootConfig.fromJson, MihomoRootConfig()),
  );
}

enum _Window with StorageEnum {
  windowRect;

  @override
  StorageMixin get target => Hives.window;
}

abstract final class WindowHive {
  static final windowRect = _Window.windowRect.readDef(
    .fromJson(WindowRect.fromJson, WindowRect.zero),
  );
}
