import 'dart:async';

import 'package:common/common.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:nop/nop.dart';
import 'package:uuid/uuid.dart';

import '../../../event/repository.dart';
import 'clash_controller.dart';

class ConfigsController with NopLifecycle {
  ConfigsController();
  late final Repository repository = getType();
  late final ClashController clash = getType();

  AMap<String, Profile> get profiles => BaseConfig.profiles;
  bool isCurrent(Profile profile) {
    return BaseConfig.currentProfile.value.isCurrent(profile);
  }

  Future<void> addNewConfigUrl(
    String url,
    String name,
    int? updateIntervalM,
  ) async {
    final data = BaseConfig.profiles.value;
    final id = Uuid().v4();

    final profile = Profile(
      id: id,
      url: url,
      name: name,
      updateInterval: updateIntervalM,
    );
    data[id] = profile;
    updateConfigData(profile);
  }

  Future<void> updateConfigUrl(Profile profile) async {
    final data = BaseConfig.profiles.value;
    data[profile.id!] = profile;
  }

  Future<void> reloadConfig(Profile profile) async {
    if (await repository.clashEvent.reloadConfigs(profile, update: true)) {
      await release(const Duration(milliseconds: 300));
      clash.getData();
    }
  }

  Future<void> updateConfigData(Profile profile) async {
    await repository.clashEvent.reloadConfigs(profile, update: false);
    await release(const Duration(milliseconds: 300));
    if (isCurrent(profile)) {
      clash.getData();
    }
  }
}
