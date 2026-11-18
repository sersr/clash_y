import 'dart:async';

import 'package:clash_service/api.dart';
import 'package:nop/nop.dart';

final class AutoUpdateProfile {
  AutoUpdateProfile(this.data, this.refresh) {
    autoUpdateProfile();
  }
  Timer? _timer;
  final Profile data;
  final Future<bool> Function() refresh;

  var _closed = false;

  void close() {
    _timer?.cancel();
    _closed = true;
    _next = .zero;
  }

  Duration _next = .zero;

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

    var delay = Duration(minutes: interval) + _next;
    _timer = Timer(delay, _onUpdate);
  }

  void _onUpdate() async {
    if (_closed) return;
    try {
      if (await refresh()) {
        autoUpdateProfile();
        _next = .zero;
        return;
      }
      _next += .new(minutes: 30);
    } catch (e) {
      _closed = true;
      _next += .new(minutes: 30);
      Log.e(e);
    }
  }
}
