import 'dart:async';

import 'package:clash_service/clash_service.dart';
import 'package:clashy/event/clash_event.dart';
import 'package:common/common.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:nop/nop.dart';

class ClashController with NopLifecycle {
  ClashController();

  static String get unixSockPath => G.unixSocketPath;

  static const _resumeRefreshCooldown = Duration(seconds: 30);

  late final ClashEvent clashEvent = getType();
  final _mainChangedNotifier = (<String, AV<int>>{});

  final _delayQueue = TaskQueue(channels: 10);
  ValueNotifier<int> getSelector(String key) {
    return _mainChangedNotifier.putIfAbsent(key, () {
      _delayQueue.run(() => getDelay(key));
      return (-1).val;
    });
  }

  final AV<ProxiesData?> _data = .val(null);
  ProxiesData? get data => _data.value;
  final AV<DateTime?> _lastRefreshTime = .val(null);
  DateTime? get lastRefreshTime => _lastRefreshTime.value;
  final _isRunning = false.val;
  bool get isRunning => _isRunning.value;

  AV<bool> get isRunningRaw => _isRunning;

  final _isStarting = false.val;
  bool get isStarting => _isStarting.value;

  Future<void> _initialization = Future<void>.value();
  var _initializationSucceeded = false;

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
    _initializationSucceeded = false;
    _initialization = _loadInitialState();
  }

  Future<void> _loadInitialState() async {
    try {
      final coreStarted = await _startCoreForInitialization();
      final remoteData = await _loadInitialProxies(coreStarted: coreStarted);
      _updateData(remoteData ?? const ProxiesData(history: [], proxies: []));
      if (remoteData != null) {
        await _syncProfileWithService();
      }
      _initializationSucceeded = true;
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

  Future<ProxiesData?> _loadInitialProxies({required bool coreStarted}) async {
    final vpnRunning = await _queryRunningState();
    if (coreStarted) {
      final data = await _waitForCore();
      if (data == null) {
        throw StateError('Clash core did not expose its controller API.');
      }
      return data;
    }
    if (!vpnRunning) return null;
    return clashEvent.clashApi.getProxies();
  }

  Future<bool> _waitForInitialization() async {
    await _initialization;
    return _initializationSucceeded;
  }

  Future<ProxiesData?> _waitForCore() async {
    for (var attempt = 0; attempt < 20; attempt++) {
      final remoteData = await clashEvent.clashApi.getProxies();
      if (remoteData != null) return remoteData;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return null;
  }

  @override
  void nopDispose() {
    _log?.cancel();
    _traffic?.cancel();
    super.nopDispose();
  }

  final _queue = TaskQueue();
  Future<void> start() async {
    if (!await _waitForInitialization()) return;
    await _queue.run(_start);
  }

  Future<void> _start() async {
    _isStarting.value = true;
    if (await _queryRunningState()) {
      _isStarting.value = false;
      return;
    }

    try {
      final profile = await _currentProfile();
      if (defaultTargetPlatform.isDesktop && await _hasOtherVpnConnection()) {
        await _queryRunningState();
        _reportError(
          'Another VPN connection or tunnel route is active. '
          'Disconnect the other VPN and try again.',
          warning: true,
        );
        return;
      }

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
        await _queryRunningState();
        _reportError('Start VPN failed.');
        return;
      }

      final remoteData = await _waitForRunningData();
      if (remoteData != null) {
        _updateData(remoteData);
      } else if (defaultTargetPlatform == TargetPlatform.android &&
          !isRunning) {
        _reportError('Android VPN did not become active.');
      } else {
        await _refreshData();
      }
    } catch (e) {
      await _queryRunningState();
      _reportError('Start Clash failed: $e');
    } finally {
      _isStarting.value = false;
    }
  }

  Future<ClashProfile> _currentProfile() async {
    final path = await clashEvent.initConfig();
    return BaseConfig.currentProfileData.value.toClashProfile(path);
  }

  Future<bool> _hasOtherVpnConnection() async {
    return ClashService.hasOtherVpnConnection();
  }

  Future<ProxiesData?> _waitForRunningData() async {
    for (var attempt = 0; attempt < 20; attempt++) {
      final remoteData = await clashEvent.clashApi.getProxies();
      if (await _queryRunningState() && remoteData != null) {
        return remoteData;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return null;
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
    await _queue.run(_refreshData);
  }

  Future<void> _refreshData() async {
    final remoteData = await clashEvent.clashApi.getProxies();
    await _queryRunningState();

    _updateData(remoteData ?? const ProxiesData(history: [], proxies: []));
  }

  void _updateData(ProxiesData data) {
    _data.value = data;
    removeProxyDelay();
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

  Future<bool> _queryRunningState() async {
    late final bool running;
    try {
      if (defaultTargetPlatform == .android) {
        running = await ClashService.isVpnActive();
      } else if (defaultTargetPlatform == .iOS) {
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
    await _queue.run(_stop);
  }

  Future<void> _stop() async {
    if (!await _queryRunningState()) return;

    if (defaultTargetPlatform == TargetPlatform.android) {
      final success = await _stopAndroidVpn();
      Log.w('close vpn: $success');
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final requested = await ClashService.stop();
      final stopped = !await _queryRunningState();
      Log.w('close vpn: ${requested && stopped}');
      return;
    }

    final success = await _stopDesktopVpn();
    Log.w('close vpn: $success');
  }

  Future<bool> _stopAndroidVpn() async {
    if (!await ClashService.stop()) {
      await _queryRunningState();
      return false;
    }

    final deadline = DateTime.now().add(const Duration(seconds: 10));
    do {
      if (!await _queryRunningState() &&
          await clashEvent.clashApi.getProxies() != null) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    } while (DateTime.now().isBefore(deadline));

    if (!isRunning) {
      _reportError('VPN stopped, but the Clash core API is unavailable.');
    } else {
      _reportError('Android VPN did not stop.');
    }
    return false;
  }

  Future<bool> _stopDesktopVpn() async {
    try {
      final response = await ClashService.stopVpn();
      if (!response.success) {
        await _queryRunningState();
        _reportError('Stop VPN failed: ${response.data}');
        return false;
      }

      final deadline = DateTime.now().add(const Duration(seconds: 10));
      do {
        if (!await _queryRunningState() &&
            await ClashService.isClashRunning()) {
          return true;
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      } while (DateTime.now().isBefore(deadline));

      _reportError(
        isRunning ? 'Desktop VPN did not stop.' : 'Clash core is unavailable.',
      );
      return false;
    } catch (e) {
      await _queryRunningState();
      _reportError('Stop VPN failed: $e');
      return false;
    }
  }

  Future<void> restart() async {
    await stop();
    await start();
  }

  Future<void> uninstall() async {
    if (!await _waitForInitialization()) return;
    final success = await ClashService.uninstall();
    await _queryRunningState();
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
