import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:utils/utils.dart';

import '../event/event.dart';
import '../event/repository.dart';
import 'clash_main_provider.dart';

class ClashConfigNotifier extends ChangeNotifier {
  ClashConfigNotifier(this.repository, this.clashMainNotifier);
  final Repository repository;
  final ClashMainNotifier clashMainNotifier;
  void getConfigs() {
    _getConfigDb();
  }

  Future<void> reloadConfig(String path) async {
    await repository.reloadConfigs(true, path);
    await release(const Duration(milliseconds: 300));
    clashMainNotifier.getData();
  }

  ConfigsCurrent? _data;
  ConfigsCurrent? get data => _data;
  List<ConfigTable>? get tables => _data?.tables;
  String get current => _data?.current ?? '';
  bool get listening => _sub != null;
  StreamSubscription<ConfigsCurrent>? _sub;
  void _getConfigDb() {
    Log.w('listen');
    _sub?.cancel();
    _sub = repository.getConfigsCurrent().listen((event) {
      if (_data != null && event == ConfigsCurrent.none) {
        notifyListeners();
        return;
      }
      _data = event;
      notifyListeners();
    }, onDone: () {
      _sub = null;
      Log.e('done');
    });
  }

  Future<void> addNewConfigUrl(
      String url, String? name, int updateInterval) async {
    await repository.addNewConfigUrl(url, updateInterval, name);
  }

  Future<void> updateConfigUrl(
      String url, String? name, int? updateInterval) async {
    await repository.updateConfigsUrl(
        url, ConfigTable(url: url, name: name, updateInterval: updateInterval));
  }

  Future<void> updateConfigData(String url) async {
    await repository.updateCurrentConfig(url);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sub = null;
    super.dispose();
  }
}
