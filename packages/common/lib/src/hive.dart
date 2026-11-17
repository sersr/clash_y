import 'package:common/common.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';

part 'hive/model.dart';
part 'hive/settings.dart';

enum Hives with StorageMixin, StorageMixinEnumBox, StorageMixinHive {
  appSettings,
  settings,
  config,
  window,
  webdav;

  static Iterable<StorageEnum> get items sync* {
    for (var item in values) {
      switch (item) {
        case Hives.settings:
          yield* SettingsHive.values;
        case Hives.config:
          yield* BaseConfig.values;
        case Hives.window:
          yield* WindowHive.values;
        case Hives.webdav:
          yield* WebDavHive.values;
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

enum WebDavHive<T> with StorageEnum<T> {
  settings<WebDavBackupSettings>(),
  lastSyncAt<String>();

  @override
  StorageMixin get target => Hives.webdav;

  @override
  StorageTransform get transform {
    return switch (this) {
      .settings => .new(WebDavBackupSettings.fromJson, WebDavBackupSettings()),
      .lastSyncAt => .base(''),
    };
  }
}

enum BaseConfig<T> with StorageEnum<T> {
  currentProfile<String>(),
  profiles<Map<String, Profile>>(),
  baseConfig<MihomoRootConfig>();

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
    }
  }

  static final currentProfileData = () {
    final id = currentProfile.value;
    return profiles.value[id] ?? Profile();
  }.val;
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
