import 'dart:async';

import 'package:clashy/event/clash_event.dart';
import 'package:common/common.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:nop/nop.dart';

class ClashConnectionController with NopLifecycle {
  late final ClashEvent clashEvent = getType();
  final AV<Connections?> _connections = .val(null);
  Connections? get connections => _connections.value;

  StreamSubscription<Connections>? _sub;

  bool get listening => _sub != null;
  final interval = Duration(seconds: 1).val;

  void watchConnections() {
    _sub?.cancel();
    _sub = clashEvent.clashApi
        .watchConnections(interval.value)
        .listen(
          (event) {
            _connections.value = event;
          },
          onDone: () {
            _sub = null;
            Log.e('done');
          },
        );
  }

  void toggle(bool active) {
    if (active) {
      if (_sub != null) return;
      watchConnections();
    } else {
      _sub?.cancel();
      _sub = null;
    }
  }

  Future<void> closeConnection(String id) async {
    await clashEvent.closeConnection(id);
  }

  @override
  void nopDispose() {
    _sub?.cancel();
    _sub = null;
    super.nopDispose();
  }
}
