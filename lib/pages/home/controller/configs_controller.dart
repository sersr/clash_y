import 'dart:async';

import 'package:common/common.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:nop/nop.dart';
import 'package:uuid/uuid.dart';

import '../../../event/repository.dart';
import '../../../event/update_profile.dart';
import 'clash_controller.dart';

class ConfigsController with NopLifecycle {
  ConfigsController();
  late final Repository repository = getType();
  late final ClashController clash = getType();

  /// Periodic profile refreshes, keyed by profile id.
  final _autoUpdates = <String, AutoUpdateProfile>{};

  AMap<String, Profile> get profiles => BaseConfig.profiles.al.al;
  bool isCurrent(Profile profile) {
    return BaseConfig.currentProfileData.value.isCurrent(profile);
  }

  @override
  void nopInit() {
    super.nopInit();
    profiles.addListener(_syncAutoUpdates);
    _syncAutoUpdates();

    clash.isRunningRaw.addListener(_syncAutoUpdates);
  }

  @override
  void nopDispose() {
    profiles.removeListener(_syncAutoUpdates);
    clash.isRunningRaw.removeListener(_syncAutoUpdates);
    _closeTimer();
    super.nopDispose();
  }

  void _closeTimer() {
    for (final entry in _autoUpdates.values) {
      entry.close();
    }
    _autoUpdates.clear();
  }

  /// Keeps one timer per profile that has an `updateInterval`.
  void _syncAutoUpdates() {
    if (!clash.isRunning) {
      _closeTimer();
      return;
    }

    final data = profiles.value;
    final scheduled = <String>{};

    for (final entry in data.entries) {
      final minutes = entry.value.updateInterval;
      if (minutes == null || minutes <= 0) continue;

      final id = entry.key;
      scheduled.add(id);
      _autoUpdates.remove(id)?.close();

      _autoUpdates[id] = .new(entry.value, () => _autoUpdate(id));
    }

    _autoUpdates.removeWhere((id, value) {
      if (scheduled.contains(id)) return false;
      value.close();
      return true;
    });
  }

  /// Downloads the profile into its cached file so it is ready the next time
  /// the user switches to it.
  ///
  /// While the VPN is off the current profile's cache is also written to
  /// `config.yaml`, so starting it later does not go back to an older
  /// subscription. When the VPN is on the service owns that file.
  Future<bool> _autoUpdate(String id) async {
    final profile = profiles.value[id];
    if (profile == null) return false;

    final apply = isCurrent(profile) && !clash.isRunning;
    final res = await repository.clashEvent.reloadConfigs(
      profile,
      updateCurrent: apply,
    );
    if (res == null) {
      return false;
    }
    return true;
  }

  Future<void> addNewConfigUrl(
    String url,
    String name,
    int? updateIntervalM,
    String? scriptId,
  ) async {
    final data = BaseConfig.profiles.value;
    final id = Uuid().v4();

    final profile = Profile(
      id: id,
      url: url,
      name: name,
      updateInterval: updateIntervalM,
      scriptId: scriptId,
    );
    data[id] = profile;
    updateConfigData(profile);
  }

  void updateProfile(Profile profile) {
    final newProfile = profiles.update(profile.id!, (v) {
      return v.copyWith(
        url: profile.url,
        name: profile.name,
        updateInterval: profile.updateInterval,
        scriptId: profile.scriptId,
      );
    });

    if (isCurrent(newProfile)) {
      BaseConfig.currentProfile.value = newProfile.id ?? '';
      clash.syncProfileWithService();
    }
  }

  Future<void> reloadConfig(Profile profile) async {
    if (await repository.clashEvent.reloadConfigs(
          profile,
          updateCurrent: true,
        ) ==
        true) {
      await release(const Duration(milliseconds: 300));
      clash.getData();
      if (isCurrent(profile) && clash.isRunning) {
        // await clash.syncProfileWithService();
      }
    }
  }

  Future<void> updateConfigData(Profile profile) async {
    await repository.clashEvent.reloadConfigs(
      profile,
      updateCurrent: false,
      refresh: true,
    );
    await release(const Duration(milliseconds: 300));
    if (isCurrent(profile)) {
      clash.getData();
    }
  }
}
