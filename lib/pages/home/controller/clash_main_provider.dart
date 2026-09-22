import 'dart:async';
import 'dart:convert';

import 'package:clashy/event/base/data.dart';
import 'package:clashy/event/repository.dart';
import 'package:clashy/init.dart';
import 'package:clashy/model/log_model.dart';
import 'package:common/common.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:nop/nop.dart';
import 'package:vpn_service/vpn_service.dart';

class ClashMainNotifier with NopLifecycle {
  ClashMainNotifier();

  late final Repository repository = getType();
  final _mainChangedNotifier = (<String, AV<int>>{});

  ValueNotifier<int> getSelector(String key) {
    return _mainChangedNotifier.putIfAbsent(key, () {
      EventQueue.run(getDelay, () => getDelay(key), channels: 10);
      return (-1).al;
    });
  }

  final AV<ProxiesData?> _data = .new(null);
  ProxiesData? get data => _data.value;

  String getName(String proxyName) {
    if (data case var data?) {
      for (var item in data.proxies) {
        if (item.name == proxyName) {
          return '$proxyName: ${item.now}';
        }
      }
    }
    return proxyName;
  }

  @override
  void nopInit() async {
    super.nopInit();

    getData();
    // await start();
    if (data?.proxies.isNotEmpty != true) {
      getData();
    }
  }

  @override
  void nopDispose() {
    _log?.cancel();
    _traffic?.cancel();
    super.nopDispose();
  }

  Future<void> start() async {
    final unixSocketPath = HiveConfig.unixSockPath;
    final path = await initConfigPath(unixSocketPath);
    Log.w('vpn configDir: $path, unixSocket: $unixSocketPath');

    final success = await VPNService.start(path);
    if (success == false) {
      Log.e('start vpn failed');
      return;
    }
  }

  Future<void> getData() async {
    final remoteData =
        await repository.clashEvent.getProxies() ??
        const ProxiesData(history: [], proxies: []);
    _data.value = remoteData;
    removeProxyDelay();
  }

  void logConfig() async {
    final data = await repository.clashEvent.gets('configs');
    Log.w((json.decode(data) as Map).logPretter);
  }

  Iterable<String> get proxyKeys sync* {
    if (data?.proxies case var list?) {
      for (var item in list) {
        if (item.all case var all?) {
          for (var i in all) {
            yield i;
          }
        }
      }
    }
  }

  Future<void> stop() async {
    final success = await VPNService.close();
    Log.w('close vpn: $success');
  }

  void removeProxyDelay() {
    final list = proxyKeys.toList();
    _mainChangedNotifier.removeWhere((e, _) => list.contains(e));
  }

  Future<void> selectProxy(String? selector, String? proxy) async {
    if (selector == null || proxy == null) return;
    return EventQueue.runOne([selector, selector], () async {
      await repository.clashEvent.selectProxy(selector, proxy);
      return getData();
    });
  }

  Future<void> getDelay(String proxy) async {
    final delay = await repository.clashEvent.getDelay(
      proxy,
      3000,
      'http://www.gstatic.com/generate_204',
    );

    getSelector(proxy).value = delay?.delay ?? 0;
  }

  StreamSubscription? _log;
  StreamSubscription? _traffic;

  void _logListen(LogModel log) {
    Log.w('l.xl: ${log.type} | ${log.payload}');
  }

  void _trafficListen(TrafficModel traffic) {
    // Log.w('${traffic.up} | ${traffic.down}');
  }

  void stopListen() {
    _log?.cancel();
    _traffic?.cancel();
    _log = null;
    _traffic = null;
  }

  void startListen() {
    if (_log != null && _traffic != null) return;
    listenLogTraffic();
  }

  void listenLogTraffic() {
    _log?.cancel();
    _traffic?.cancel();
    _log = repository.clashEvent
        .watchLogs('debug')
        .listen(
          _logListen,
          onDone: () => _log = null,
          onError: (e) => _log = null,
        );

    _traffic = repository.clashEvent.watchTraffic().listen(
      _trafficListen,
      onDone: () => _traffic = null,
      onError: (e) => _traffic = null,
    );
  }
}
