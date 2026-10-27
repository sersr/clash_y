part of '../hive.dart';

enum _Settings with StorageEnum {
  allowApplications,
  disAllowApplications,

  mixedPort,
  allowLan,
  mode,
  ipv6,
  logLevel,

  /// tun
  tunEnabled,
  tunStack,

  ///

  applicationListMode;

  @override
  StorageMixin get target => Hives.settings;
}

abstract final class SettingsHive {
  static final allowApplications = _Settings.allowApplications.readDef(
    .list(<String>[]),
  );
  static final disAllowApplications = _Settings.disAllowApplications.readDef(
    .list(<String>[]),
  );

  static final applicationListMode = _Settings.applicationListMode.readDef(
    .def(ApplicationListMode.fromJson, ApplicationListMode.none),
  );

  /// clash
  static final mixedProt = _Settings.mixedPort.readDef(.nInt(7890));
  static final allowLan = _Settings.allowLan.readDef(.boolean(false));
  static final mode = _Settings.mode.readDef(
    .def(SettingMode.fromJson, SettingMode.direct),
  );

  static final ipv6 = _Settings.ipv6.readDef(.boolean(true));
  static final logLevel = _Settings.logLevel.readDef(
    .def(ClashLogLevel.fromJson, ClashLogLevel.info),
  );

  /// tun
  static final tunEnabled = _Settings.tunEnabled.readDef(.boolean(false));
  static final tunStack = _Settings.tunStack.readDef(
    .def(ClashTunStack.fromJson, ClashTunStack.mixed),
  );
}
