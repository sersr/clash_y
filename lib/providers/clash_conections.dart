import 'package:flutter/foundation.dart';
import 'package:utils/utils.dart';
import 'dart:async';
import '../data/data.dart';
import '../event/repository.dart';

class ClashConnectionsNotifier extends ChangeNotifier {
  ClashConnectionsNotifier(this.repository);
  final Repository repository;
  Connections? _connections;
  Connections? get connections => _connections;

  StreamSubscription<Connections>? _sub;

  bool get listening => _sub != null;

  void watchConnections() {
    _sub?.cancel();
    _sub = repository.watchConnections().listen((event) {
      _connections = event;
      notifyListeners();
    }, onDone: () {
      _sub = null;
      Log.e('done');
    });
  }

  void pause() {
    _sub?.pause();
  }
  void resume() {
    _sub?.resume();
  }
  void pauseOrResume(bool paused) {
    if(paused) {
      pause();
    }else{
      resume();
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }
}
