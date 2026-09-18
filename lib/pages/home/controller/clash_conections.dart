import 'dart:async';

import 'package:flutter_nop/flutter_nop.dart';
import 'package:nop/nop.dart';

import '../../../data/data.dart';
import '../../../event/repository.dart';

class ClashConnectionsNotifier with NopLifecycle {
  ClashConnectionsNotifier();
  late final Repository repository = getType();
  final AV<Connections?> _connections = .new(null);
  Connections? get connections => _connections.value;

  StreamSubscription<Connections>? _sub;

  bool get listening => _sub != null;
  final interval = Duration(seconds: 1).al;

  void watchConnections() {
    _sub?.cancel();
    _sub = repository.clashEvent
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

  @override
  void nopDispose() {
    _sub?.cancel();
    _sub = null;
    super.nopDispose();
  }
}
