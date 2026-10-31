import 'dart:async';

import 'package:clashy/event/repository.dart';
import 'package:common/common.dart';
import 'package:flutter_nop/flutter_nop.dart';

final class UpdateProfileData {
  final String id;
  final int? updateIntervalM;

  new(this.id, this.updateIntervalM);
  new from(Profile data)
    : id = data.id ?? '',
      updateIntervalM = data.updateInterval;

  Duration? get updateInterval {
    if (updateIntervalM == null) return null;
    if (updateIntervalM case var u? when u <= 0) return null;
    return Duration(minutes: updateIntervalM ?? 0);
  }

  @override
  int get hashCode => Object.hash(id, updateIntervalM);

  @override
  bool operator ==(Object other) {
    if (other is! UpdateProfileData) return false;
    return runtimeType == other.runtimeType &&
        id == other.id &&
        updateIntervalM == other.updateIntervalM;
  }
}

extension on Profile {
  UpdateProfileData get data => .from(this);
}

mixin AutoUpdateProfileMixin on NopLifecycle {
  Timer? _timer;
  Profile? _data;

  late final repo = getType<Repository>();
  void autoUpdateProfile(Profile data) {
    if (_data == data) return;
    final lastData = _data?.data;
    final currentData = data.data;
    _data = data;
    if (lastData == currentData) return;
    _timer?.cancel();

    final interval = currentData.updateInterval;
    if (interval == null) return;
    _timer = Timer.periodic(interval, _onUpdate);
  }

  void _onUpdate(Timer timer) {
    if (_data case var data?) {
      repo.clashEvent.reloadConfigs(data);
    }
  }
}
