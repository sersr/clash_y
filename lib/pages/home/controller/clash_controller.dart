import 'dart:async';

import 'package:clash_service/clash_service.dart' hide fs;
import 'package:clashy/event/base/data.dart';
import 'package:clashy/event/impl/clash_service.dart';
import 'package:clashy/event/repository.dart';
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

  AV<bool> get isRunningRaw => _isRunning;

  final _isStarting = false.al;
  bool get isStarting => _isStarting.value;

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
      ProxiesData? remoteData;
      var coreStarted = false;
      if (defaultTargetPlatform == TargetPlatform.android) {
        final path = await initConfigPath();
        final profile = BaseConfig.currentProfile.value.toClashProfile(path);
        final accepted = await ClashService.startCore(
          profile,
          controllerSocketPath: BaseConfig.unixSockPath.value,
        );
        if (accepted) {
          coreStarted = true;
        } else {
          const message = 'Failed to start the Clash core service.';
          Log.e(message);
          showMsg(message);
        }
      } else if (defaultTargetPlatform.isDesktop) {
        final profile = await _currentProfile();
        final serviceStarted = await ClashService.start(
          profile,
          controllerSocketPath: BaseConfig.unixSockPath.value,
          trayClashSocket: BaseConfig.unixSockPath.value,
        );
        if (!serviceStarted) {
          _reportError('Failed to start the Clash service.');
        } else {
          coreStarted = true;
          if (!await ClashServiceApi.isVpnActive()) {
            final response = await ClashServiceApi.startClashCore(profile);
            coreStarted = response.success;
            if (!response.success) {
              _reportError('Failed to start the Clash core: ${response.data}');
            }
          }
        }
      }

      final running = await _queryRunningState();
      if (coreStarted) {
        remoteData ??= await _waitForCore();
        if (remoteData == null) {
          _reportError('Clash core did not expose its controller API.');
        }
      } else if (running) {
        remoteData ??= await repository.clashEvent.getProxies();
      }
      _data.value = remoteData ?? const ProxiesData(history: [], proxies: []);
      removeProxyDelay();
      if (remoteData != null) {
        await syncProfileWithService();
      }
    } catch (e) {
      _reportError('Load Clash state failed: $e');
    }
  }

  Future<ProxiesData?> _waitForCore() async {
    for (var attempt = 0; attempt < 20; attempt++) {
      final remoteData = await repository.clashEvent.getProxies();
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
  Future<void> start() => _queue.run(_start);

  Future<void> _start() async {
    _isStarting.value = true;
    if (await _queryRunningState()) {
      _isStarting.value = false;
      return;
    }

    try {
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
        controllerSocketPath: BaseConfig.unixSockPath.value,
        trayClashSocket: BaseConfig.unixSockPath.value,
      );
      if (!started) {
        await _queryRunningState();
        _reportError('Start VPN failed.');
        return;
      }

      if (defaultTargetPlatform.isDesktop && await _hasOtherVpnConnection()) {
        await _queryRunningState();
        _reportError(
          'Another VPN connection or tunnel route is active. '
          'Disconnect the other VPN and try again.',
          warning: true,
        );
        return;
      }

      if (defaultTargetPlatform.isDesktop &&
          !await _startDesktopCore(profile)) {
        await _queryRunningState();
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
    final path = await initConfigPath();
    return BaseConfig.currentProfile.value.toClashProfile(path);
  }

  Future<bool> _hasOtherVpnConnection() async {
    return ClashService.hasOtherVpnConnection();
  }

  Future<bool> _startDesktopCore(ClashProfile profile) async {
    if (!await ClashService.isInstalled()) {
      _reportError('Clash service is not installed.');
      return false;
    }
    return _run(profile);
  }

  Future<ProxiesData?> _waitForRunningData() async {
    for (var attempt = 0; attempt < 20; attempt++) {
      final remoteData = await repository.clashEvent.getProxies();
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

  Future<bool> _run(ClashProfile profile) async {
    if (!defaultTargetPlatform.isDesktop) return true;

    try {
      final coreResponse = await ClashServiceApi.startClashCore(profile);
      if (!coreResponse.success) {
        _reportError('Start Clash core failed: ${coreResponse.data}');
        return false;
      }

      final vpnResponse = await ClashServiceApi.startVpn(profile);
      if (!vpnResponse.success) {
        _reportError('Start VPN failed: ${vpnResponse.data}');
        return false;
      }
      if (!await ClashServiceApi.isVpnActive()) {
        _reportError('VPN did not become active.');
        return false;
      }
      return true;
    } catch (e) {
      _reportError('Start Clash failed: $e');
      return false;
    }
  }

  /// Pushes the profile the app currently uses to the running service so it
  /// refreshes `config.yaml` from the right subscription while the app is in
  /// the background.
  Future<void> syncProfileWithService() async {
    final profile = BaseConfig.currentProfile.value;
    if (profile.url == null &&
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    final clashProfile = profile.toClashProfile(configYaml.parent.path);
    try {
      if (defaultTargetPlatform.isDesktop) {
        await ClashServiceApi.updateClashProfile(clashProfile);
      } else {
        await ClashService.updateProfile(
          clashProfile,
          controllerSocketPath: BaseConfig.unixSockPath.value,
        );
      }
    } catch (e) {
      Log.e('sync profile with service failed: $e');
    }
  }

  Future<void> getData() async {
    await _queue.run(_refreshData);
  }

  Future<void> _refreshData() async {
    final remoteData = await repository.clashEvent.getProxies();
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
        running = ClashService.isVpnActive();
      } else if (defaultTargetPlatform == .iOS) {
        running = await repository.clashEvent.getProxies() != null;
      } else {
        running = await ClashServiceApi.isVpnActive();
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
    return _queue.run(_stop);
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
          await repository.clashEvent.getProxies() != null) {
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
      final response = await ClashServiceApi.stopVpn();
      if (!response.success) {
        await _queryRunningState();
        _reportError('Stop VPN failed: ${response.data}');
        return false;
      }

      final deadline = DateTime.now().add(const Duration(seconds: 10));
      do {
        if (!await _queryRunningState() &&
            await ClashServiceApi.isClashRunning()) {
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
