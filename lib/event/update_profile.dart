import 'dart:async';

import 'package:common/common.dart';
import 'package:nop/nop.dart';

final class AutoUpdateProfile {
  AutoUpdateProfile(this.data, this.refresh) {
    autoUpdateProfile();
  }
  Timer? _timer;
  final Profile data;
  final Future<void> Function() refresh;

  var _closed = false;

  void close() {
    _timer?.cancel();
    _closed = true;
  }

  void autoUpdateProfile() {
    _timer?.cancel();
    if (_closed) return;

    var interval = data.updateInterval;
    final lastUpdate = data.updateTime;
    if (interval == null) return;
    final rawInt = interval;
    if (rawInt <= 0) return;

    if (lastUpdate == null) {
      interval = 0;
    } else {
      final now = DateTime.now();
      interval = interval - now.difference(lastUpdate).inMinutes;
    }

    interval = interval.clamp(0, rawInt);

    var delay = Duration(minutes: interval);
    _timer = Timer(delay, _onUpdate);
  }

  void _onUpdate() async {
    if (_closed) return;
    try {
      await refresh();
    } catch (e) {
      Log.e(e);
    }
    autoUpdateProfile();
  }
}
