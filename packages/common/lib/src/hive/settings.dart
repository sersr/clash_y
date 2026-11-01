part of '../hive.dart';

enum SettingsHive<T> with StorageEnum<T> {
  allowApplications<List<String>>(),
  disAllowApplications<List<String>>(),

  mixedPort<int>(),
  allowLan<bool>(),
  mode<SettingMode>(),
  ipv6<bool>(),
  logLevel<ClashLogLevel>(),

  /// tun
  tunEnabled<bool>(),
  tunStack<ClashTunStack>(),

  ///

  applicationListMode<ApplicationListMode>();

  @override
  StorageTransform get transform {
    switch (this) {
      case .allowApplications:
      case .disAllowApplications:
        return .list(<String>[]);
      case .applicationListMode:
        return .new(ApplicationListMode.fromJson, ApplicationListMode.none);
      case .mixedPort:
        return .base(7890);
      case .allowLan:
        return .base(false);
      case .mode:
        return .new(SettingMode.fromJson, SettingMode.direct);
      case .ipv6:
        return .base(true);
      case .logLevel:
        return .new(ClashLogLevel.fromJson, ClashLogLevel.info);
      case .tunEnabled:
        return .base(false);
      case .tunStack:
        return .new(ClashTunStack.fromJson, ClashTunStack.mixed);
    }
  }

  @override
  StorageMixin get target => Hives.settings;
}
