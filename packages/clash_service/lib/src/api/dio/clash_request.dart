import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';

import 'package:clash_service/src/api/dio/unix_socket_http.dart';
import 'package:dio/dio.dart';
import 'package:nop/nop.dart';

import '../model/_g.dart';
import 'unix_socket_dio.dart';

final class ClashApi {
  ClashApi({required this.appConfigPath, required this.unixSocketPath}) {
    init();
  }
  final String appConfigPath;
  final String unixSocketPath;
  late Dio _dio;

  void init() {
    _dio = Dio(
      BaseOptions(
        baseUrl: 'http://localhost/',
        headers: {Headers.contentTypeHeader: Headers.jsonContentType},
      ),
    );

    _dio.httpClientAdapter = UnixSocketAdapter(unixSocketPath);
  }

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

  Stream<TrafficModel> watchTraffic() async* {
    try {
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

  Stream<LogModel> watchLogs(String level) async* {
    try {
      final response = await _dio.get<ResponseBody>(
        'logs',
        options: Options(responseType: ResponseType.stream),
        queryParameters: {'level': level},
      );
      final data = response.data;

      if (data != null) {
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

  String generateWebSocketKey() {
    // 1. 生成 16 个字节的随机数
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));

    // 2. 将其转换为 Base64 字符串
    return base64.encode(bytes);
  }

  Stream<Connections> watchConnections(Duration interval) async* {
    try {
      final socket = await io.WebSocket.connect(
        'ws://localhost/connections?interval=${interval.inMilliseconds}',
        customClient: createUnixSocketClient(unixSocketPath),
      );

      yield* socket.map((message) {
        switch (message) {
          case List<int> bytes:
            try {
              final v = utf8.decode(bytes);
              final data = jsonDecode(v);
              if (data case Map data) {
                final s = Connections.fromJson(data.cast());
                return s;
              }
            } catch (e) {
              Log.e('error: $e');
            }
          case String text:
            try {
              final data = jsonDecode(text);
              if (data case Map data) {
                final s = Connections.fromJson(data.cast());
                return s;
              }
            } catch (e) {
              Log.e('error: $e');
            }
        }

        return Connections();
      });
    } catch (e, s) {
      Log.e("$e, $s");
    }
  }

  Future<void> closeConnection(String id) async {
    try {
      await _dio.delete<void>('connections/$id');
    } catch (e, s) {
      Log.e('close connection failed: $e\n$s');
      rethrow;
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

  Future<void> selectProxy(String selector, String proxy) async {
    try {
      Log.i('$selector : $proxy');
      await _dio.put(
        'proxies/${Uri.encodeComponent(selector)}',
        data: {'name': proxy},
      );
    } on DioException catch (e) {
      Log.e('${e.response}');
    }
  }

  FutureOr<void> getRules() async {
    final data = await gets('rules');
    Log.i('all Rules: $data');
  }

  Future<void> updateConfigPath(String path) async {
    final response = await _dio.put(
      'configs',
      data: {'path': path},
      queryParameters: {'force': true},
    );
    Log.i(response.data);
  }

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
    } on DioException catch (_) {
      // if (e.response case var res?) {
      // Log.w(res.data);
      // return null;
      // }
      // Log.w('${e.response?.data}\n$s');
    }
    return null;
  }
}
