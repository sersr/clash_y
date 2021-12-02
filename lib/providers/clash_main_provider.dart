import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:useful_tools/useful_tools.dart';

import '../event/event.dart';
import '../event/repository.dart';

class ClashMainNotifier extends ChangeNotifier {
  ClashMainNotifier(this.repository);

  final Repository repository;
  final _mainChangedNotifier = (<String, ValueNotifier<int>>{});

  ValueNotifier<int> getSelector(String key) {
    return _mainChangedNotifier.putIfAbsent(key, () {
      EventQueue.runTaskOnQueue(getDelay, () => getDelay(key),channels: 5);
      return ValueNotifier(-1);
    });
  }

  ProxiesData? _data;
  ProxiesData? get data => _data;

  Future<void> getData() async {
    final remoteData = await repository.getProxies() ??
        const ProxiesData(history: [], proxies: []);
    _data = remoteData;
    notifyListeners();
  }

  Timer? _timer;
  void removeDisposeListener() {
    Log.e('....');
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 3), () {
      _mainChangedNotifier.removeWhere((key, value) => !value.hasListeners);
    });
  }

  Future<void> selectProxy(String? selector, String? proxy) async {
    if (selector == null || proxy == null) return;
    return EventQueue.runOneTaskOnQueue([selector, selector], () async {
      await repository.selectProxy(selector, proxy);
      return getData();
    });
  }

  Future<void> getDelay(String proxy) async {
    final delay = await repository.getDelay(
        proxy, 3000, 'http://www.gstatic.com/generate_204');

    getSelector(proxy).value = delay?.delay ?? 0;
  }
}
