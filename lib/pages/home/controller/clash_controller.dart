import 'dart:async';
import 'dart:convert';

import 'package:clash_service/clash_service.dart';
import 'package:clashy/event/base/data.dart';
import 'package:clashy/event/impl/clash_service.dart';
import 'package:clashy/event/repository.dart';
import 'package:clashy/init.dart';
import 'package:common/common.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:nop/nop.dart';

class ClashController with NopLifecycle {
  ClashController();

  static const _resumeRefreshCooldown = Duration(seconds: 30);

  late final Repository repository = getType();
  final _mainChangedNotifier = (<String, AV<int>>{});

  final _delayQueue = TaskQueue(channels: 10);
  ValueNotifier<int> getSelector(String key) {
    return _mainChangedNotifier.putIfAbsent(key, () {
      _delayQueue.run(() => getDelay(key));
      return (-1).al;
    });
  }

  final AV<ProxiesData?> _data = .val(null);
  ProxiesData? get data => _data.value;
  final AV<DateTime?> _lastRefreshTime = .val(null);
  DateTime? get lastRefreshTime => _lastRefreshTime.value;
  final _isRunning = false.al;
  bool get isRunning => _isRunning.value;

  final map = <String, int?>{};
  late final ss = map.al;
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
    await _loadInitialState();
  }

  Future<void> _loadInitialState() async {
    try {
      _isRunning.value = await _queryRunningState();
      final remoteData = _isRunning.value
          ? await repository.clashEvent.getProxies()
          : null;
      _data.value = remoteData ?? const ProxiesData(history: [], proxies: []);
      removeProxyDelay();
    } finally {}
  }

  @override
  void nopDispose() {
    _log?.cancel();
    _traffic?.cancel();
    super.nopDispose();
  }

  final _queue = TaskQueue();
  Future<void> start() async {
    if (isRunning) return;
    _queue.run(() async {
      final isAllowList = SettingsHive.applicationListMode.value == 'whitelist';
      final allowedApplications = SettingsHive.allowApplications.value;

      final unixSocketPath = BaseConfig.unixSockPath.value;
      final path = await initConfigPath(unixSocketPath);

      final success = await ClashService.start(
        path,
        allowList: isAllowList,
        allowedApplications: isAllowList ? allowedApplications : const [],
        disallowedApplications: isAllowList
            ? const []
            : SettingsHive.disAllowApplications.value,
      );
      if (success == false) {
        Log.e('start vpn failed');
        return;
      }

      if (defaultTargetPlatform.isDesktop) {
        if (!await ClashService.isInstalled()) {
          Log.e('desktop service is not installed');
          return;
        }
        if (!await _run(path)) return;
      }
      _isRunning.value = true;

      getData();
    });
  }

  Future<bool> _run(String configPath) async {
    if (!defaultTargetPlatform.isDesktop) return true;

    try {
      final response = await ClashServiceApi.startClash(configPath);
      if (!response.success) {
        Log.e('start Clash failed: ${response.data}');
        return false;
      }
      return await ClashServiceApi.isClashRunning();
    } catch (e) {
      Log.e(e);
      return false;
    }
  }

  Future<void> getData() async {
    _queue.run(() async {
      final remoteData = await repository.clashEvent.getProxies();

      _isRunning.value = await _queryRunningState(
        apiAvailable: remoteData != null,
      );

      final data = remoteData ?? const ProxiesData(history: [], proxies: []);
      _data.value = data;
      removeProxyDelay();
    });
  }

  Future<void> refreshOnResume() async {
    final now = DateTime.now();
    final lastRefresh = lastRefreshTime;
    if (lastRefresh != null &&
        now.difference(lastRefresh) < _resumeRefreshCooldown) {
      return;
    }
    _lastRefreshTime.value = now;
    await getData();
  }

  Future<bool> _queryRunningState({bool? apiAvailable}) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      if (apiAvailable != null) return apiAvailable;
      return await repository.clashEvent.getProxies() != null;
    }
    try {
      if (!await ClashService.isInstalled()) return false;
      return await ClashServiceApi.isClashRunning();
    } catch (e) {
      Log.e('check Clash status failed: $e');
      return false;
    }
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
    if (!isRunning) return;

    return _queue.run(() async {
      var success = false;

      if (defaultTargetPlatform == .android) {
        success = await ClashService.stop();
        if (success) {
          _isRunning.value = false;
        }

        Log.w('close vpn: $success');
        return;
      }

      if (!await ClashService.isInstalled()) {
        _isRunning.value = false;
        return;
      }

      try {
        final response = await ClashServiceApi.stopClash();
        Log.w('stop clash: ${response.success}, ${response.data}');
        _isRunning.value = await _queryRunningState();
        success = response.success && !_isRunning.value;
      } catch (e) {
        _isRunning.value = await _queryRunningState();
      }

      Log.w('close vpn: $success');
    });
  }

  Future<void> uninstall() async {
    final success = await ClashService.uninstall();
    Log.w('close vpn: $success');
  }

  void removeProxyDelay() {
    final list = proxyKeys.toList();
    _mainChangedNotifier.removeWhere((e, _) => list.contains(e));
  }

  Future<void> selectProxy(String? selector, String? proxy) async {
    if (selector == null || proxy == null) return;
    return EventQueue.runOne([selector, proxy], () async {
      await repository.clashEvent.selectProxy(selector, proxy);
      return getData();
    });
  }

  Future<void> getDelay(String proxy) async {
    final delay = await repository.clashEvent.getDelay(proxy, 3000, testUrl);

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
    if (_log != null) return;
    listenLogTraffic();
  }

  void listenLogTraffic() async {
    _log?.cancel();
    _traffic?.cancel();
    _log = repository.clashEvent
        .watchLogs('debug')
        .listen(
          _logListen,
          cancelOnError: true,
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
