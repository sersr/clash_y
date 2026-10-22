part of '../hive.dart';

enum _Settings with StorageEnum {
  allowApplications,
  disAllowApplications;

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
}
