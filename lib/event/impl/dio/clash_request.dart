import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:math';

import 'package:clashy/event/impl/dio/unix_socket_http.dart';
import 'package:clashy/event/repository.dart';
import 'package:common/common.dart';
import 'package:dio/dio.dart';
import 'package:file/file.dart';
import 'package:nop/nop.dart';
import 'package:path/path.dart';

import '../../event.dart';
import 'unix_socket_dio.dart';

final class ClashRequest implements ClashEvent {
  ClashRequest({required this.paths, required this.repo}) {
    init();
  }
  String get appConfigPath => paths.appConfigPath;
  String get unixSocketPath => BaseConfig.unixSockPath.value;
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

  void updateUnixSocket() {
    BaseConfig.unixSockPath.value = join(
      paths.appSupportPath,
      'socket_${Random().nextInt(65556)}.sock',
    );
    _dio.httpClientAdapter = UnixSocketAdapter(unixSocketPath);
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
      final bytes = await fs.currentDirectory.childFile(path).readAsString();
      // final file = fs.currentDirectory
      //     .childDirectory(G.appCachePath)
      //     .childFile('configt.yaml');
      final file = configYaml;
      final text = await configYaml.readAsString();

      await file.create(recursive: true);
      await file.writeAsString(bytes);
      await _mergeAndroidTunConfig(file);
      final text2 = await configYaml.readAsString();
      final response = await _dio.put(
        'configs',
        data: {'path': file.path},
        queryParameters: {'force': true},
      );
      Log.w(text);
      Log.w(text2);
      Log.i(response.data);
    } catch (e) {
      Log.i(e);
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
      Log.w('${e.response?.data}\n$s');
    }
    return null;
  }

  /// mihomo disables runtime config update on Android by default. The core
  /// enables PUT /configs again, but the new config must keep the current TUN
  /// file descriptor. Otherwise ReCreateTun would close the VpnService fd and
  /// try to create a new TUN device without root.
  Future<void> _mergeAndroidTunConfig(File file) async {
    if (io.Platform.isAndroid == false) {
      return;
    }

    final current = await gets('configs');
    if (current.isEmpty) {
      return;
    }

    try {
      final decoded = jsonDecode(current);
      if (decoded is Map) {
        final tun = decoded['tun'];
        if (tun is Map) {
          final fd = tun['file-descriptor'];
          if (fd is int && fd > 0) {
            final normalized = Map<String, Object?>.from(tun);
            normalized.remove('inet4-address');
            normalized['enable'] = true;
            final editor = YamlUtils.edit(await file.readAsString());
            editor.update(['tun'], normalized);
            await file.writeAsString(editor.toString());
          }
        }
      }
    } catch (e) {
      Log.w('merge Android TUN config failed: $e');
    }
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

  Future<void> onClashInit() async {
    final current = BaseConfig.currentProfile;
    if (current.value != null) {
      final file = getFile('${current.value}');
      if (file.existsSync()) {
        return reloadConfigs(true, file.path);
      }
    }
  }

  @override
  FutureOr<void> updateCurrentConfig(String url) async {
    final current = BaseConfig.currentProfile.value;
    await reloadConfigs(true, url, update: true, reload: url == current);
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
              headers: {'User-Agent': 'clash/mihomo'},
            ),
          );
          final fileData = responseFile.data;
          final info =
              responseFile.headers['subscription-userinfo']?.firstOrNull ?? '';
          Log.w("header: $info");
          if (fileData != null) {
            final editor = YamlUtils.edit(fileData);

            updateDelegateConfig(editor);
            final fileTemp = file.parent.childFile('$baseName.temp');
            if (!await fileTemp.exists()) {
              await fileTemp.create(recursive: true);
            }
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
            BaseConfig.currentProfile.value = url;
            await updateConfig(force, file.path);
          }
        }
      } catch (e) {
        Log.i(e);
        BaseConfig.currentProfile.value = url;
        await updateConfig(force, file.path);
      }
    });
  }

  void updateDelegateConfig(YamlEditor editor) {
    // 'external-controller-unix': paths.unixSocketPath,
    Log.w(editor.toString());
    editor
      ..update(['log-level'], 'info')
      ..update(['mode'], 'rule')
      ..update(['mixed-port'], 7890)
      ..update(['alown-lan'], false)
      ..update(['dns'], defaultDnsConfig());
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
  }
}
