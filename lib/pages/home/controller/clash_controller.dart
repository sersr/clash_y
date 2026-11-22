import 'dart:async';

import 'package:clash_service/clash_service.dart';
import 'package:clashy/event/clash_event.dart';
import 'package:common/common.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:nop/nop.dart';

class ClashController with NopLifecycle, AlScopeManager {
  ClashController();

  static String get unixSockPath => G.unixSocketPath;

  late final ClashEvent clashEvent = getType();
  final _mainChangedNotifier = (<String, AV<int>>{});

  final _delayQueue = TaskQueue(channels: 10);
  ValueNotifier<int> getSelector(String key) {
    return _mainChangedNotifier.putIfAbsent(key, () {
      _delayQueue.run(() => getDelay(key));
      return (-1).val;
    });
  }

  final DataStatusScopeDy<ProxiesData> _data = .idle();
  ProxiesData? get data => _data.data.data;

  final AV<DateTime?> _lastRefreshTime = .val(null);
  DateTime? get lastRefreshTime => _lastRefreshTime.value;
  final _isRunning = false.val;
  bool get isRunning => _isRunning.value;

  AV<bool> get isRunningRaw => _isRunning;

  final loading = false.val;
  bool get isLoading => loading.value;

  Future<void> _initialization = Future<void>.value();

  final map = <String, int?>{};
  late final ss = map.val;
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
  void nopInit() {
    super.nopInit();
    _initialization = _loadInitialState();
    startLoop();
    _loop();
  }

  Timer? _timer;

  void startLoop() {
    if (!mounted) return;
    if (_timer case var timer? when timer.isActive) return;

    _timer = Timer(const Duration(seconds: 5), _loop);
  }

  final _timerQueue = TaskQueue();
  Future<void> _loop() async {
    if (_timerQueue.actived) return _timerQueue.runner;

    await _timerQueue.run(() async {
      await _data.load(() async {
        try {
          final remoteData = await clashEvent.clashApi.getProxies();
          if (remoteData != null) {
            _data.success(remoteData);
          } else {
            _data.failure("get null.");
          }
        } catch (e, s) {
          _data.failure(e.toString(), s);
        }
        await _queryRunningState();
        Log.w('running: $isRunning');
      });
    });

    startLoop();
  }

  Future<void> _loadInitialState() async {
    try {
      await _startCoreForInitialization();
      await _syncProfileWithService();
    } catch (error, stackTrace) {
      Log.e('Load Clash state failed: $error\n$stackTrace');
      showMsg('Load Clash state failed: $error');
    }
  }

  Future<bool> _startCoreForInitialization() async {
    final platform = defaultTargetPlatform;
    if (platform != TargetPlatform.android && !platform.isDesktop) return false;

    await ClashService.updateDesktopServiceIfOutdated(
      controllerSocketPath: G.unixSocketPath,
    );

    final profile = await _currentProfile();
    final started = await ClashService.startCore(
      profile,
      controllerSocketPath: unixSockPath,
    );
    if (!started) {
      throw StateError('Failed to start the Clash core.');
    }
    return true;
  }

  Future<bool> _waitForInitialization() async {
    await _initialization;
    return true;
  }

  @override
  void nopDispose() {
    _log?.cancel();
    _traffic?.cancel();
    _timer?.cancel();
    super.nopDispose();
  }

  final _queue = TaskQueue();
  Future<void> start() async {
    if (!await _waitForInitialization()) return;

    final task = _queue.run(_start)..whenComplete(_loop);
    await task;
  }

  Future<void> _start() async {
    loading.value = true;
    try {
      if (defaultTargetPlatform.isDesktop && await _hasOtherVpnConnection()) {
        _reportError(
          'Another VPN connection or tunnel route is active. '
          'Disconnect the other VPN and try again.',
          warning: true,
        );
        return;
      }

      final profile = await _currentProfile();
      final mode = SettingsHive.applicationListMode.value;
      final started = await ClashService.start(
        profile,
        allowList: mode == .whiteList,
        allowedApplications: mode == .whiteList
            ? SettingsHive.allowApplications.value
            : const <String>[],
        disallowedApplications: mode == .blackList
            ? SettingsHive.disAllowApplications.value
            : const <String>[],
        controllerSocketPath: unixSockPath,
      );
      if (!started) {
        _reportError('Start VPN failed.');
        return;
      }
    } catch (e) {
      _reportError('Start Clash failed: $e');
    } finally {
      loading.value = false;
    }
  }

  Future<ClashProfile> _currentProfile() => clashEvent.currentClashProfile();

  Future<bool> _hasOtherVpnConnection() async {
    return ClashService.hasOtherVpnConnection();
  }

  void _reportError(String message, {bool warning = false}) {
    if (warning) {
      Log.w(message);
    } else {
      Log.e(message);
    }
    showMsg(message);
  }

  /// Pushes the profile the app currently uses to the running service so it
  /// refreshes `config.yaml` from the right subscription while the app is in
  /// the background.
  Future<void> syncProfileWithService() async {
    if (!await _waitForInitialization()) return;
    await _syncProfileWithService();
  }

  Future<void> _syncProfileWithService() async {
    final profile = BaseConfig.currentProfileData.value;
    if (profile.url == null) {
      return;
    }

    final clashProfile = profile.toClashProfile(configYaml.parent.path);
    try {
      if (defaultTargetPlatform.isDesktop) {
        await ClashService.updateClashProfile(clashProfile);
      } else {
        await ClashService.updateProfile(
          clashProfile,
          controllerSocketPath: unixSockPath,
        );
      }
    } catch (e) {
      Log.e('sync profile with service failed: $e');
    }
  }

  Future<void> getData() async {
    if (!await _waitForInitialization()) return;
    return _loop();
  }

  Future<bool> _queryRunningState() async {
    late final bool running;
    try {
      if (defaultTargetPlatform == .iOS) {
        running = await clashEvent.clashApi.getProxies() != null;
      } else {
        running = await ClashService.isVpnActive();
      }
    } catch (e) {
      Log.e('check Clash status failed: $e');
      running = false;
    }

    if (isRunning != running) {
      _isRunning.value = running;
    }
    return running;
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

  Future<void> stop() {
    return _stopAfterInitialization();
  }

  Future<void> _stopAfterInitialization() async {
    if (!await _waitForInitialization()) return;
    final task = _queue.run(_stop)..whenComplete(_loop);
    await task;
  }

  Future<void> _stop() async {
    loading.value = true;
    try {
      final success = await ClashService.stop();
      Log.w('close vpn: $success');
    } catch (_) {}
    loading.value = false;
  }

  Future<void> restart() async {
    await stop();
    await start();
  }

  Future<void> uninstall() async {
    if (!await _waitForInitialization()) return;
    final success = await ClashService.uninstall();
    _loop();
    Log.w('close vpn: $success');
  }

  void removeProxyDelay() {
    final list = proxyKeys.toList();
    _mainChangedNotifier.removeWhere((e, _) => list.contains(e));
  }

  Future<void> selectProxy(String? selector, String? proxy) async {
    if (selector == null || proxy == null) return;
    if (!await _waitForInitialization()) return;
    return EventQueue.runOne([selector, proxy], () async {
      await clashEvent.clashApi.selectProxy(selector, proxy);
      return getData();
    });
  }

  Future<void> getDelay(String proxy) async {
    if (!await _waitForInitialization()) return;
    final delay = await clashEvent.clashApi.getDelay(proxy, 3000, testUrl);

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
    unawaited(listenLogTraffic());
  }

  Future<void> listenLogTraffic() async {
    if (!await _waitForInitialization()) return;
    _log?.cancel();
    _traffic?.cancel();
    _log = clashEvent.clashApi
        .watchLogs('debug')
        .listen(
          _logListen,
          cancelOnError: true,
          onDone: () => _log = null,
          onError: (e) => _log = null,
        );

    _traffic = clashEvent.clashApi.watchTraffic().listen(
      _trafficListen,
      onDone: () => _traffic = null,
      onError: (e) => _traffic = null,
    );
  }
}
