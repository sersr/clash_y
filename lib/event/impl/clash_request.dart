import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:utils/utils.dart';

import '../../data/data.dart';
import '../event.dart';
import 'dio_base.dart';

mixin ClashRequestMixin on DioInitMixin implements ClashEvent {
  @override
  FutureOr<ProxiesData?> getProxies() async {
    final data = await gets('proxies');
    try {
      final Map<String, Object?> map = json.decode(data);
      final histories = <History>[];
      final proxies = <ProxyItem>[];
      for (var item in map.entries) {
        final h = item.value;
        if (h is Map<String, dynamic>) {
          for (var item in h.entries) {
            if (item.value is Map<String, dynamic>) {
              final proxy = ProxyItem.fromJson(item.value);
              if (proxyHasData(proxy)) {
                proxies.add(proxy);
                continue;
              }
              final history = History.fromJson(item.value);
              if (history.history != null && history.name != null) {
                history.history!.sort((a, b) {
                  final aTime = DateTime.tryParse('${a?.time}');
                  final bTime = DateTime.tryParse('${b?.time}');
                  return aTime != null && bTime != null
                      ? aTime.millisecondsSinceEpoch -
                          bTime.millisecondsSinceEpoch
                      : 0;
                });
                histories.add(history);
              }
            }
          }
        }
      }
      return ProxiesData(history: histories, proxies: proxies);
    } catch (e) {
      Log.e(e);
    }
  }

  Future<void> getTraffic() async {
    try {
      final response = await dio.get<ResponseBody>('traffic',
          options: Options(responseType: ResponseType.stream));
      final data = response.data?.stream;
      if (data != null) {
        final _sub = data.listen((event) {
          final s = utf8.decode(event);
          Log.i('Traffic: $s', onlyDebug: false);
        });
        Timer(const Duration(seconds: 10), () {
          _sub.cancel();
        });
      }
    } catch (e) {
      Log.e(e);
    }
  }

  Future<void> getLogs(String level) async {
    try {
      final response = await dio.get<ResponseBody>('logs',
          options: Options(responseType: ResponseType.stream),
          queryParameters: {'level': level});
      final data = response.data?.stream;
      if (data != null) {
        final _sub = data.listen((event) {
          final s = utf8.decode(event);
          Log.i('Logs: $s', onlyDebug: false);
        });
        Timer(const Duration(seconds: 10), () {
          _sub.cancel();
        });
      }
    } catch (e) {
      Log.e(e);
    }
  }

  Future<String> gets(String q) async {
    try {
      final response = await dio.get<String>(q);
      final data = response.data;
      if (data != null) {
        return data;
      }
    } catch (e) {
      Log.e(e);
    }
    return '';
  }

  @override
  Future<void> selectProxy(String selector, String proxy) async {
    try {
      Log.i('$selector : $proxy', onlyDebug: false);
      await dio.put('proxies/${Uri.encodeComponent(selector)}',
          data: {'name': proxy});
    } on DioError catch (e) {
      Log.e('${e.response}');
    }
  }

  @override
  FutureOr<void> getRules() async {
    final data = await gets('rules');
    Log.i('all Rules: $data', onlyDebug: false);
  }

  @override
  FutureOr<void> getConfigs() async {
    final data = await gets('configs');
    Log.i('all Configs: $data', onlyDebug: false);
  }

  @override
  FutureOr<void> reloadConfigs(bool force, String path) async {
    try {
      final response =
          await dio.put<String>('configs?force=$force', data: {'path': path});
      Log.i(response.data);
    } on DioError catch (e) {
      Log.i(e.response);
    }
  }

  @override
  FutureOr<void> resetConfigs(ConfigsData data) async {
    try {
      final response = await dio.patch<String>('configs', data: data.body);
      Log.i(response.data);
    } catch (e) {
      Log.i(e);
    }
  }

  @override
  FutureOr<Delay?> getDelay(String proxy, int timeout, String testUrl) async {
    try {
      final response = await dio.get<String>(
          'proxies/${Uri.encodeComponent(proxy)}/delay',
          queryParameters: {
            'timeout': timeout,
            'url': testUrl,
          });
      final data = response.data;
      if (data != null) {
        return Delay.fromJson(jsonDecode(data));
      }
    } on DioError catch (e) {
      Log.w(e.response);
    }
  }

  StreamController<Connections>? _controller;
  @override
  Stream<Connections> watchConnections() {
    if (_controller != null) {
      return _controller!.stream;
    }
    final controller = StreamController<Connections>(
        onListen: _reset,
        onCancel: () => _controller = null,
        onPause: () => _reset(true),
        onResume: _reset);

    _controller = controller;
    return controller.stream;
  }

  void _reset([bool close = false]) {
    _timer?.cancel();
    if (!close) _timer = Timer.periodic(const Duration(seconds: 2), _onTimer);
  }

  Timer? _timer;
  void _onTimer(Timer t) {
    if (_controller != null) {
      EventQueue.runOneTaskOnQueue(_onTimer, () async {
        final data = await getConnections();
        if (_controller != null && data != null) {
          _controller!.add(data);
        }
      });
      return;
    }
    t.cancel();
    _timer = null;
  }

  Future<Connections?> getConnections() async {
    try {
      final response = await dio.get<String>('connections');
      final data = response.data;
      if (data != null) {
        return Connections.fromJson(jsonDecode(data));
      }
    } on DioError catch (e) {
      Log.i(e.response);
    }
  }
}
