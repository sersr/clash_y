import 'dart:async';

import 'package:flutter_nop/flutter_nop.dart';

import '../../../data/data.dart';
import '../../../event/repository.dart';

class ClashConnectionsNotifier with NopLifecycle {
  ClashConnectionsNotifier();
  late final Repository repository = getType();
  final AV<Connections?> _connections = .new(null);
  Connections? get connections => _connections.value;

  StreamSubscription<Connections>? _sub;

  bool get listening => _sub != null;

  @override
  void nopInit() {
    super.nopInit();
    watchConnections();
  }

  void watchConnections() {
    // _sub?.cancel();
    // _sub = repository.watchConnections().listen(
    //   (event) {
    //     _connections.value = event;
    //   },
    //   onDone: () {
    //     _sub = null;
    //     Log.e('done');
    //   },
    // );
  }

  void pause() {
    _sub?.pause();
  }

  void resume() {
    _sub?.resume();
  }

  void pauseOrResume(bool paused) {
    if (paused) {
      pause();
    } else {
      resume();
    }
  }

  @override
  void nopDispose() {
    _sub?.cancel();
    _sub = null;
    super.nopDispose();
  }
}
