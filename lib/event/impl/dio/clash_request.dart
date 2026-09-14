import 'dart:async';
import 'dart:convert';

import 'package:clash_y/event/repository.dart';
import 'package:dio/dio.dart';
import 'package:nop/nop.dart';
import 'package:path/path.dart';

import '../../../data/data.dart';
import '../../../model/log_model.dart';
import '../../event.dart';
import 'unix_socket_dio.dart';

mixin ClashRequestMixin on Resolve implements ClashEvent {
  String get appConfigPath;
  String get unixSocketPath;
  late Dio _dio;

  @override
  void initStateListen(add) {
    super.initStateListen(add);
    // client = HttpClient()..findProxy = _findProxy;

    _dio = Dio(
      BaseOptions(
        baseUrl: 'http://localhost/',
        headers: {Headers.contentTypeHeader: Headers.jsonContentType},
      ),
    );

    _dio.httpClientAdapter = UnixSocketAdapter(unixSocketPath);
  }

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
    return null;
  }

  @override
  Stream<TrafficModel> watchTraffic() async* {
    try {

      // final socket = await createUnixSocket(unixSocketPath);

      final response = await _dio.get<ResponseBody>(
        'traffic',
        options: Options(responseType: ResponseType.stream),
      );
      final data = response.data?.stream;
      if (data != null) {
        yield* data.map((event) {
          try {
            final data = jsonDecode(utf8.decode(event));
            if (data case Map data) {
              final s = TrafficModel.fromJson(data.cast());
              return s;
            }
          } catch (e) {
            Log.e('error: $e');
          }
          return TrafficModel();
        });
      }
    } catch (e) {
      Log.e(e);
    }
  }

  @override
  Stream<LogModel> watchLogs(String level) async* {
    try {

      final response = await _dio.get<ResponseBody>(
        'logs',
        options: Options(responseType: ResponseType.stream),
        queryParameters: {'level': level},
      );
      final data = response.data;

      if ( data != null) {
      final stream = data.stream;

        yield* stream.map((event) {
          try {
            final data = jsonDecode(utf8.decode(event));
            if (data case Map data) {
              final s = LogModel.fromJson(data.cast());
              return s;
            }
          } catch (e) {
            Log.e('error: $e');
          }
          return LogModel();
        });
      }
    } catch (e) {
      Log.e(e);
    }
  }

  Future<String> gets(String q) async {
    try {
      final response = await _dio.get<String>(q);
      final data = response.data;
      if (data != null) {
        return data;
      }
    } catch (e, s) {
      Log.e('$e\n$s');
    }
    return '';
  }

  @override
  Future<void> selectProxy(String selector, String proxy) async {
    try {
      await getConfigs();
      Log.i('$selector : $proxy');
      await _dio.put(
        'proxies/${Uri.encodeComponent(selector)}',
        data: {'name': proxy},
      );
    } on DioException catch (e) {
      Log.e('${e.response}');
    }
  }

  @override
  FutureOr<void> getRules() async {
    final data = await gets('rules');
    Log.i('all Rules: $data');
  }

  @override
  FutureOr<void> getConfigs() async {
    final data = await gets('configs');
    Log.i('all Configs: $data');
  }

  @override
  FutureOr<void> reloadConfigs(bool force, String path) async {
    try {
      // final bytes = await fs.currentDirectory.childFile(path).readAsBytes();
      final file = fs.currentDirectory.childFile(
        join(appConfigPath, 'configt.yaml'),
      );
      // await file.create(recursive: true);
      // await file.writeAsBytes(bytes);
      final response = await _dio.put<String>(
        'configs?force=$force',
        data: {'path': file.path},
      );
      Log.i(response.data);
    } on DioException catch (e) {
      Log.i(e.response);
    }
  }

  @override
  FutureOr<void> resetConfigs(ConfigsData data) async {
    try {
      final response = await _dio.patch<String>('configs', data: data.body);
      Log.i(response.data);
    } catch (e) {
      Log.i(e);
    }
  }

  @override
  FutureOr<Delay?> getDelay(String proxy, int timeout, String testUrl) async {
    try {
      final response = await _dio.get<String>(
        'proxies/${Uri.encodeComponent(proxy)}/delay',
        queryParameters: {'timeout': timeout, 'url': testUrl},
      );
      final data = response.data;
      if (data != null) {
        return Delay.fromJson(jsonDecode(data));
      }
    } on DioException catch (e, s) {
      Log.w('$e\n$s');
    }
    return null;
  }

  // @override
  // Stream<Connections> watchConnections() {
  // if (_controller != null) {
  //   return _controller!.stream;
  // }
  // final controller = StreamController<Connections>(
  //   onListen: _reset,
  //   onCancel: () => _controller = null,
  //   onPause: () => _reset(true),
  //   onResume: _reset,
  // );

  // _controller = controller;
  // return controller.stream;
  // }

  // void _reset([bool close = false]) {
  //   _timer?.cancel();
  //   if (!close) _timer = Timer.periodic(const Duration(seconds: 2), _onTimer);
  // }

  // Timer? _timer;
  // void _onTimer(Timer t) {
  //   if (_controller != null) {
  //     EventQueue.runOne(_onTimer, () async {
  //       final data = await getConnections();
  //       if (_controller != null && data != null) {
  //         _controller!.add(data);
  //       }
  //     });
  //     return;
  //   }
  //   t.cancel();
  //   _timer = null;
  // }

  Future<Connections?> getConnections() async {
    try {
      final response = await _dio.get<String>('connections');
      final data = response.data;
      if (data != null) {
        return Connections.fromJson(jsonDecode(data));
      }
    } on DioException catch (e) {
      Log.i(e.response);
    }
    return null;
  }
}
