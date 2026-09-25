import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clash_service/clash_service.dart';
import 'package:clashy/event/base/data.dart';
import 'package:clashy/event/impl/clash_service.dart';
import 'package:clashy/event/impl/dio/unix_socket_http.dart';
import 'package:clashy/event/repository.dart';
import 'package:clashy/init.dart';
import 'package:clashy/model/log_model.dart';
import 'package:common/common.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:nop/nop.dart';

class ClashController with NopLifecycle {
  ClashController();

  late final Repository repository = getType();
  final _mainChangedNotifier = (<String, AV<int>>{});

  final _delayQueue = TaskQueue(channels: 10);
  ValueNotifier<int> getSelector(String key) {
    return _mainChangedNotifier.putIfAbsent(key, () {
      _delayQueue.run(() => getDelay(key));
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

    final success = await ClashService.start(path);
    if (success == false) {
      Log.e('start vpn failed');
      return;
    }

    _run(path);
  }

  void _run(String configPath) async {
    if (!Platform.isMacOS) return;

    try {
      final s = await ClashServiceApi.startClash(
        .new(args: ['-d', configPath]),
      );
      Log.w(s);
    } catch (e) {
      Log.e(e);
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
    final success = await ClashService.close();
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
  StreamSubscription? _logService;
  StreamSubscription? _traffic;

  void _logListen(LogModel log) {
    Log.w('l.xl: ${log.type} | ${log.payload}');
  }

  void _trafficListen(TrafficModel traffic) {
    // Log.w('${traffic.up} | ${traffic.down}');
  }

  void stopListen() {
    _log?.cancel();
    _logService?.cancel();
    _traffic?.cancel();
    _log = null;
    _traffic = null;
  }

  void startListen() {
    serviceLog();
    // if (_log != null && _traffic != null) return;
    // listenLogTraffic();
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

  void serviceLog() async {
    _logService?.cancel();
    final socket = await WebSocket.connect(
      "ws://localhost:7887/clash/ws",
      customClient: createUnixSocketClient(clashSocket),
    );
    _logService?.cancel();

    late StreamController controller;
    controller = StreamController(onCancel: () => socket.close());

    controller.addStream(socket);
    socket.done.whenComplete(() => _logService = null);

    _logService = controller.stream.listen((data) {
      Log.w(data);
    });
  }
}
