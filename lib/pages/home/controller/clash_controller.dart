import 'dart:async';

import 'package:clash_service/clash_service.dart';
import 'package:clashy/event/clash_event.dart';
import 'package:common/common.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nop/nop.dart';

class ClashController with NopLifecycle, AlScopeManager {
  ClashController();

  late final ClashEvent clashEvent = getType();

  /// Controller lifetime, used to poll faster and to stay quiet while the core
  /// is still coming up.
  final _boot = Stopwatch()..start();

  bool get _isBooting => _boot.elapsed < const Duration(seconds: 30);
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

  bool get isActived => _data.data is DataSuccess;

  final _isRunning = false.val;
  bool get isRunning => _isRunning.value;

  AV<bool> get isRunningRaw => _isRunning;

  final DataStatusScope<Null, Null> loading = .idle();
  bool get isLoading {
    return loading.data is StatusLoading;
  }

  Future<void> _initialization = Future<void>.value();

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

  late AppLifecycleListener appLifecycleListener;
  @override
  void nopInit() {
    super.nopInit();
    _initialization = _loadInitialState();
    startLoop();
    _loop();
    appLifecycleListener = .new(onHide: _onHide, onResume: _onResume);
  }

  @override
  void nopDispose() {
    _log?.cancel();
    _traffic?.cancel();
    _timer?.cancel();

    appLifecycleListener.dispose();
    super.nopDispose();
  }

  final _shown = true.val;
  void _onHide() {
    _timer?.cancel();
    _shown.value = false;
  }

  void _onResume() {
    _shown.value = true;
    startLoop();
  }

  Timer? _timer;

  void startLoop() {
    if (!mounted) return;
    if (_timer case var timer? when timer.isActive) return;
    if (!_shown.value) return;

    // While the core is still coming up on the first run, poll quickly so the
    // proxy list is not blank for a full 5s round trip; settle afterwards.
    _timer = Timer(
      isActived
          ? const .new(seconds: 30)
          : (_isBooting ? const .new(seconds: 1) : const .new(seconds: 5)),
      _loop,
    );
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
          } else if (!_isBooting) {
            _data.failure("get null.");
          }
        } catch (e, s) {
          // The core needs a moment to come up on launch; a refused socket in
          // that window is expected, so keep the state and retry silently.
          if (!_isBooting) _data.failure(e.toString(), s);
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
      await _pushProfileToService();
    } catch (error, stackTrace) {
      Log.e('Load Clash state failed: $error\n$stackTrace');
      showMsg('Load Clash state failed: $error');
    }
    _loop();
  }

  Future<void> _startCoreForInitialization() async {
    final platform = defaultTargetPlatform;
    if (platform != TargetPlatform.android && !platform.isDesktop) return;

    // Only desktop installs a daemon; Android starts the core inside the app.
    if (platform.isDesktop) {
      await ClashService.updateDesktopServiceIfOutdated(
        controllerSocketPath: G.unixSocketPath,
      );
    }

    final profile = await _currentProfile();
    final started = await ClashService.startCore(
      profile,
      controllerSocketPath: G.unixSocketPath,
    );
    if (!started) {
      throw StateError(
        'Failed to start the Clash core (service startup failed).',
      );
    }
    if (platform == TargetPlatform.android) {
      // The intent only asks the :vpn process to start; its control socket
      // appears once the core is up, so do not announce the profile before.
      await ClashService.waitForService();
    }
  }

  final _queue = TaskQueue();
  Future<void> start() async {
    await _initialization;

    final task = loading.load(() => _queue.run(_start))..whenComplete(_loop);
    await task;
  }

  Future<void> _start() async {
    try {
      if (defaultTargetPlatform.isDesktop &&
          await ClashService.hasOtherVpnConnection()) {
        _reportError(
          'Another VPN connection or tunnel route is active. '
          'Disconnect the other VPN and try again.',
          warning: true,
        );
        return;
      }

      final profile = await _currentProfile();
      final mode = SettingsHive.applicationListMode.value;
      final started = await ClashService.startVpn(
        profile,
        allowList: mode == .whiteList,
        allowedApplications: mode == .whiteList
            ? SettingsHive.allowApplications.value
            : const <String>[],
        disallowedApplications: mode == .blackList
            ? SettingsHive.disAllowApplications.value
            : const <String>[],
        controllerSocketPath: G.unixSocketPath,
      );
      if (!started) {
        _reportError('Start VPN failed.');
        return;
      }
      if (!defaultTargetPlatform.isDesktop) {
        // The tunnel now serves the control API: hand it the schedule, so it
        // keeps refreshing while the app is in the background. Only the
        // schedule is stored — the app already wrote config.yaml.
        await ClashService.waitForService();
        await ClashService.updateProfile(
          profile,
          refresh: false,
          controllerSocketPath: G.unixSocketPath,
        );
      }
    } catch (e) {
      _reportError('Start Clash failed: $e');
    }
  }

  Future<ClashProfile> _currentProfile() => clashEvent.currentClashProfile();

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
    await _initialization;
    await _pushProfileToService();
  }

  Future<void> _pushProfileToService() async {
    final profile = BaseConfig.currentProfileData.value;
    if (profile.url == null) return;

    final clashProfile = profile.toClashProfile(configYaml.parent.path);
    try {
      // Announce the profile and its schedule only. The service owns the timer
      // and downloads the subscription when it is actually due; asking it to
      // download here would block startup for seconds and re-apply the config
      // right after the core came up. A false result only means the service is
      // not up yet, and the profile is picked up on the next start.
      final pushed = await ClashService.updateProfile(
        clashProfile,
        refresh: false,
        controllerSocketPath: G.unixSocketPath,
      );
      if (!pushed) {
        Log.w('the service does not accept profiles yet; profile kept');
        return;
      }
      Log.i('profile refreshed through the service control API');
    } catch (e) {
      Log.e('sync profile with service failed: $e');
    }
  }

  Future<void> getData() async {
    await _initialization;
    return _loop();
  }

  Future<bool> _queryRunningState() async {
    late final bool running;
    try {
      running = await ClashService.isVpnActive();
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
    await _initialization;
    final task = loading.load(() => _queue.run(_stop));
    await task;
  }

  Future<void> _stop() async {
    try {
      final success = await ClashService.stopVpn();
      await _loop();
      Log.w('close vpn: $success');
    } catch (_) {}
  }

  Future<void> restart() async {
    if (!isRunning) return;
    await ClashService.stopVpn();
    await start();
  }

  Future<void> uninstall() async {
    if (!defaultTargetPlatform.isDesktop) return;
    await _initialization;
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
    await _initialization;
    return EventQueue.runOne([selector, proxy], () async {
      await clashEvent.clashApi.selectProxy(selector, proxy);
    });
  }

  Future<void> getDelay(String proxy) async {
    await _initialization;
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
    await _initialization;
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
