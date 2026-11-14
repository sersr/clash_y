import 'package:common/common.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart';

part 'hive/model.dart';
part 'hive/settings.dart';

enum Hives with StorageMixin, StorageMixinEnumBox, StorageMixinHive {
  appSettings,
  settings,
  config,
  window;

  static Iterable<StorageEnum> get items sync* {
    for (var item in values) {
      switch (item) {
        case Hives.settings:
          yield* SettingsHive.values;
        case Hives.config:
          yield* BaseConfig.values;
        case Hives.window:
          yield* WindowHive.values;
        case .appSettings:
          yield* AppSettings.values;
      }
    }
  }

  static Iterable<Future<Box>> _openAll() =>
      values.map((e) => Hive.openBox(e.name));

  static Future<void> init(String path) {
    Hive.init(path);
    return _openAll().wait;
  }
}

enum BaseConfig<T> with StorageEnum<T> {
  currentProfile<String>(),
  profiles<Map<String, Profile>>(),
  baseConfig<MihomoRootConfig>(),
  unixSockPath<String>();

  @override
  StorageMixin get target => Hives.config;

  @override
  StorageTransform get transform {
    switch (this) {
      case .currentProfile:
        return .base('');
      case .profiles:
        return .map(Profile.fromJson, <String, Profile>{});
      case .baseConfig:
        return .new(MihomoRootConfig.fromJson, MihomoRootConfig());
      case .unixSockPath:
        return .base(
          defaultTargetPlatform == .windows
              ? r"\\.\pipe\clashy.pipe"
              : join(G.appCachePath, 'clash_config', 'socket_clash.sock'),
        );
    }
  }

  static final currentProfileData = () {
    final id = currentProfile.value;
    return profiles.value[id] ?? Profile();
  }.al;
}

enum WindowHive<T> with StorageEnum<T> {
  windowRect<WindowRect>();

  @override
  StorageMixin get target => Hives.window;

  @override
  StorageTransform get transform {
    switch (this) {
      case WindowHive.windowRect:
        return .new(WindowRect.fromJson, WindowRect.zero);
    }
  }
}

enum AppSettings<T> with StorageEnum<T> {
  themeMode<ThemeMode>();

  @override
  StorageMixin get target => Hives.appSettings;

  @override
  StorageTransform get transform {
    return switch (this) {
      .themeMode => .new(
        (data) => ThemeMode.values[data % ThemeMode.values.length],
        ThemeMode.system,
      ),
    };
  }
}
