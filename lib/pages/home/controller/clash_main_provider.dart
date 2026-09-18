import 'dart:async';
import 'dart:math';

import 'package:clash_y/event/base/data.dart';
import 'package:clash_y/event/repository.dart';
import 'package:clash_y/init.dart';
import 'package:clash_y/model/log_model.dart';
import 'package:common/common.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:nop/nop.dart';
import 'package:path/path.dart';
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
    await start();
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
    final initPathAsync = initConfigPath(HiveConfig.unixSockPath);
    final r = await VPNService.installHelper();
    Log.w('register: $r');
    final path = await initPathAsync;

    await VPNService.start(path);
    await Future.delayed(const Duration(seconds: 1));

    final rv = await VPNService.start(path);
    Log.w('start: $rv');
    SystemProxyManager().disable();
  }

  Future<void> getData() async {
    final remoteData =
        await repository.clashEvent.getProxies() ??
        const ProxiesData(history: [], proxies: []);
    _data.value = remoteData;
    removeProxyDelay();
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

  void stop() {
    VPNService.stop();

    HiveConfig.unixSocketPath = join(
      Repository.paths.appSupportPath,
      'socket_${Random().nextInt(65556)}.sock',
    );
    repository.clashEvent.update();
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
    Log.w('${log.type} | ${log.payload}');
  }

  void _trafficListen(TrafficModel traffic) {
    Log.w('${traffic.up} | ${traffic.down}');
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
