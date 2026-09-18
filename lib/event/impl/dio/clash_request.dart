import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';

import 'package:clash_y/event/impl/dio/unix_socket_http.dart';
import 'package:clash_y/event/repository.dart';
import 'package:common/common.dart';
import 'package:dio/dio.dart';
import 'package:file/file.dart';
import 'package:hive_ce/hive.dart';
import 'package:nop/nop.dart';
import 'package:path/path.dart';

import '../../../data/data.dart';
import '../../../model/log_model.dart';
import '../../event.dart';
import 'unix_socket_dio.dart';

abstract final class _BoxKey {
  static const current = 'current';
}

final class ClashRequest implements ClashEvent {
  ClashRequest({required this.paths, required this.repo}) {
    init();
  }
  String get appConfigPath => paths.appConfigPath;
  String get unixSocketPath => HiveConfig.unixSockPath;
  final Repository repo;
  final Paths paths;
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

  void update() {
    // _dio.close();
    _dio.httpClientAdapter = UnixSocketAdapter(unixSocketPath);
    // init();
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

  @override
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
              Log.w(v);
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

  FutureOr<void> updateConfig(bool force, String path) async {
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

  String get appCachePath => join(paths.appPath, 'caches');

  String getBaseNameFromUrl(String url) {
    return basename(url);
  }

  File getFile(String url) {
    return fs.currentDirectory.childFile(
      join(appCachePath, getBaseNameFromUrl(url)),
    );
  }

  final dlConfigDio = Dio();

  Box get _box => Hives.config;

  Future<void> onClashInit() async {
    final current = await _box.get(_BoxKey.current);
    if (current != null) {
      final file = getFile('$current');
      if (file.existsSync()) {
        return reloadConfigs(true, file.path);
      }
    }
  }

  @override
  FutureOr<void> updateCurrentConfig(String url) async {
    final current = _box.get(_BoxKey.current);
    await reloadConfigs(true, url, update: true, reload: url == current);
  }

  @override
  Future<String?> getCurrentConfig() async {
    final current = await _box.get(_BoxKey.current);
    if (current is String) {
      return current;
    }
    return null;
  }

  /// clashEvent

  FutureOr<void> reloadConfigs(
    bool force,
    String url, {
    bool update = false,
    bool reload = true,
  }) async {
    return EventQueue.runOne(reloadConfigs, () async {
      final file = getFile(url);
      final baseName = file.path;

      try {
        final fileExists = file.existsSync();
        final config = await repo.configsEvent.getConfig(url);

        if (!fileExists || update || config?.shouldUpdate() == true) {
          Log.w('update: $url');

          final responseFile = await dlConfigDio.get<String>(
            url,
            options: .new(
              responseType: ResponseType.plain,
              headers: {'User-Agent': 'clash'},
            ),
          );
          final fileData = responseFile.data;
          final info =
              responseFile.headers['subscription-userinfo']?.firstOrNull ?? '';
          Log.w("header: $info");
          if (fileData != null) {
            final editor = YamlUtils.edit(json.encode(fileData));

            updateDelegateConfig(editor);
            final fileTemp = file.parent.childFile('$baseName.temp');
            fileTemp.writeAsStringSync(editor.toString());
            if (!fileExists) {
              file.createSync(recursive: true);
            }
            fileTemp.renameSync(file.path);
            await repo.configsEvent.setConfigDateTime(url, info);
          }
        }
        final exists = file.existsSync();
        if (exists) {
          Log.w('$exists $file');
          if (reload) {
            await _box.put(_BoxKey.current, url);
            await updateConfig(force, file.path);
          }
        }
      } catch (e) {
        Log.i(e);
        await _box.put(_BoxKey.current, url);
        await updateConfig(force, file.path);
      }
    });
  }

  void updateDelegateConfig(YamlEditor editor) {
    editor.update([], {
      // 'external-controller-unix': paths.unixSocketPath,
      'log-level': 'info',
      'mode': 'rule',
      'mixed-port': 7890,
      'allown-lan': false,
      // ipv6:
      // ntp:
      // geodata-mode:
      // geox-url:
      // geo-auto-update:
      // geo-update-interval: 24
      // rule-providers:
      //
      //
      // 'dns':
      // 'rules':
    });
  }
}
