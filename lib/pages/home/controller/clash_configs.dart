import 'dart:async';

import 'package:flutter_nop/flutter_nop.dart';
import 'package:nop/nop.dart';

import '../../../event/event.dart';
import '../../../event/repository.dart';
import 'clash_main_provider.dart';

class ClashConfigNotifier with NopLifecycle {
  ClashConfigNotifier();
  late final Repository repository = getType();
  late final ClashMainNotifier clashMainNotifier = getType();

  @override
  void nopInit() {
    super.nopInit();
    getConfigs();
  }

  void getConfigs() {
    _getConfigDb();
  }

  Future<void> reloadConfig(String path) async {
    await repository.reloadConfigs(true, path);
    await release(const Duration(milliseconds: 300));
    clashMainNotifier.getData();
  }

  final AV<ConfigsCurrent?> _data = .new(null);
  ConfigsCurrent? get data => _data.value;
  List<ConfigTable>? get tables => data?.tables;
  String get current => data?.current ?? '';
  bool get listening => _sub != null;
  StreamSubscription<ConfigsCurrent>? _sub;
  void _getConfigDb() {
    Log.w('listen');
    _sub?.cancel();
    _sub = repository.getConfigsCurrent().listen(
      (event) {
        _data.value = event;
      },
      onDone: () {
        _sub = null;
        Log.e('done');
      },
    );
  }

  Future<void> addNewConfigUrl(
    String url,
    String? name,
    int updateInterval,
  ) async {
    await repository.addNewConfigUrl(url, updateInterval, name);
  }

  Future<void> updateConfigUrl(
    String url,
    String? name,
    int? updateInterval,
  ) async {
    await repository.updateConfigsUrl(
      url,
      ConfigTable(url: url, name: name, updateInterval: updateInterval),
    );
  }

  Future<void> updateConfigData(String url) async {
    await repository.updateCurrentConfig(url);
  }

  @override
  void nopDispose() {
    _sub?.cancel();
    _sub = null;
    super.nopDispose();
  }
}
