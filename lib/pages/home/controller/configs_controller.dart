import 'dart:async';

import 'package:flutter_nop/flutter_nop.dart';
import 'package:nop/nop.dart';

import '../../../event/event.dart';
import '../../../event/repository.dart';
import 'clash_controller.dart';

class ConfigsController with NopLifecycle {
  ConfigsController();
  late final Repository repository = getType();
  late final ClashController clash = getType();

  @override
  void nopInit() {
    super.nopInit();
    getConfigs();
  }

  void getConfigs() {
    _getConfigDb();
  }

  Future<void> reloadConfig(String path) async {
    await repository.clashEvent.reloadConfigs(true, path);
    await release(const Duration(milliseconds: 300));
    clash.getData();
    final c = repository.clashEvent.getCurrentConfig() ?? '';
    _current.value = c;
  }

  final AV<ConfigsCurrent?> _data = .new(null);
  ConfigsCurrent? get data => _data.value;
  List<ConfigTable>? get tables => data?.tables;
  final _current = ''.al;
  String get current => _current.value;

  bool get listening => _sub != null;
  StreamSubscription<ConfigsCurrent>? _sub;
  void _getConfigDb() async {
    Log.w('listen');
    _sub?.cancel();
    _sub = repository.configsEvent.getConfigsCurrent().listen(
      (event) {
        _data.value = event;
      },
      onDone: () {
        _sub = null;
        Log.e('done');
      },
      onError: (e) {
        _sub = null;
        Log.w('error: $e.');
      },
    );
    final c = repository.clashEvent.getCurrentConfig() ?? '';
    _current.value = c;
  }

  Future<void> addNewConfigUrl(
    String url,
    String? name,
    int updateInterval,
  ) async {
    await repository.configsEvent.addNewConfigUrl(url, updateInterval, name);
  }

  Future<void> updateConfigUrl(
    String url,
    String? name,
    int? updateInterval,
  ) async {
    await repository.configsEvent.updateConfigsUrl(
      url,
      ConfigTable(url: url, name: name, updateInterval: updateInterval),
    );
  }

  Future<void> updateConfigData(String url) async {
    await repository.clashEvent.updateCurrentConfig(url);
    final c = repository.clashEvent.getCurrentConfig() ?? '';
    _current.value = c;
  }

  @override
  void nopDispose() {
    _sub?.cancel();
    _sub = null;
    super.nopDispose();
  }
}
