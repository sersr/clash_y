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

final class ClashRequest {
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
    } catch (e) {
      Log.e(e);
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

  FutureOr<void> getRules() async {
    final data = await gets('rules');
    Log.i('all Rules: $data');
  }

  FutureOr<void> getConfigs() async {
    final data = await gets('configs');
    Log.i('all Configs: $data');
  }

  FutureOr<void> updateConfig(String path) async {
    try {
      if (path != configYaml.path) {
        final currentFile = fs.currentDirectory.childFile(path);

        await currentFile.copy(configYaml.path);
      }

      final configPath = await initConfigPath();

      final response = await _dio.put(
        'configs',
        data: {'path': configPath},
        queryParameters: {'force': true},
      );
      // Log.w(text);
      // Log.w(text2);
      Log.i(response.data);
    } catch (e) {
      Log.i(e);
    }
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

  String get appCachePath => join(paths.appPath, 'caches');

  String getBaseNameFromUrl(String url) {
    return basename(url);
  }

  File getFile(String url) {
    return fs.currentDirectory.childFile(
      join(appCachePath, getBaseNameFromUrl(url)),
    );
  }

  Map<String, int> _parseSubscriptionUserInfo(String info) {
    final values = <String, int>{};
    for (final part in info.split(';')) {
      final separator = part.indexOf('=');
      if (separator < 0) continue;

      final key = part.substring(0, separator).trim().toLowerCase();
      if (key != 'upload' &&
          key != 'download' &&
          key != 'total' &&
          key != 'expire') {
        continue;
      }

      final value = int.tryParse(part.substring(separator + 1).trim());
      if (value != null) values[key] = value;
    }
    return values;
  }

  final dlConfigDio = Dio();

  /// The freshest copy of [profile] known to the store.
  ///
  /// Queued refreshes may have been started with a profile that has since been
  /// updated (or just downloaded by another tick), so the queued task re-reads
  /// it instead of trusting the captured snapshot.
  Profile _latestProfile(Profile profile) {
    final id = profile.id;
    if (id == null) return profile;
    return BaseConfig.profiles.value[id] ?? profile;
  }

  FutureOr<bool> reloadConfigs(Profile profile, {bool update = false}) async {
    if (profile.url == null) return false;

    final res = await EventQueue.runOne(reloadConfigs, () async {
      profile = _latestProfile(profile);
      final url = profile.url;
      if (url == null) return false;

      var file = getFile(url);

      try {
        final fileExists = file.existsSync();
        final config = profile;

        if (!fileExists || config.shouldUpdate()) {
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
          final disposition = responseFile.headers['content-disposition'];

          final fileName = getFilenameFromContentDisposition(
            disposition?.join(''),
          );
          final userInfo = _parseSubscriptionUserInfo(info);

          profile = profile.copyWith(
            rawName: fileName,
            upload: userInfo['upload'],
            download: userInfo['download'],
            total: userInfo['total'],
            expire: userInfo['expire'],
            updateTime: DateTime.now(),
          );
          if (profile.id case var id?) {
            BaseConfig.profiles[id] = profile;
          }

          final baseName = file.path;

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
          }
        }
      } catch (e) {
        Log.e(e);
      }

      final exists = await file.exists();
      if (update) {
        BaseConfig.currentProfile.value = profile;
        if (exists) {
          Log.w('$exists $file');
          await updateConfig(file.path);
          return true;
        }
      }
      return false;
    });

    return res ?? false;
  }

  void updateDelegateConfig(YamlEditor editor) {
    Log.w(editor.toString());
    editor
      ..update([
        'log-level',
      ], const bool.fromEnvironment('dart.vm.product') ? 'warning' : 'debug')
      ..update(['mode'], 'rule')
      ..update(['mixed-port'], 7890)
      ..update(['allow-lan'], false)
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

String? getFilenameFromContentDisposition(String? header) {
  if (header == null || header.isEmpty) return null;

  // 1) 优先解析 RFC 5987 的 filename*=charset'lang'encoded
  final starMatch = RegExp(
    r"filename\*\s*=\s*([^']*)'[^']*'([^;]+)",
    caseSensitive: false,
  ).firstMatch(header);

  if (starMatch != null) {
    final charset = (starMatch.group(1) ?? 'UTF-8').toUpperCase();
    final encoded = starMatch.group(2)!.trim();
    try {
      if (charset == 'ISO-8859-1') {
        // 逐字节 %XX 解码后按 latin1 还原
        final bytes = <int>[];
        for (var i = 0; i < encoded.length; i++) {
          if (encoded[i] == '%' && i + 2 < encoded.length) {
            bytes.add(int.parse(encoded.substring(i + 1, i + 3), radix: 16));
            i += 2;
          } else {
            bytes.add(encoded.codeUnitAt(i));
          }
        }
        return String.fromCharCodes(bytes);
      }
      return Uri.decodeComponent(encoded); // UTF-8
    } catch (_) {
      // 解码失败就继续尝试普通 filename
    }
  }

  // 2) 普通 filename=，支持带引号（含转义 \"）和不带引号
  final match = RegExp(
    r'''filename\s*=\s*(?:"((?:[^"\\]|\\.)*)"|([^;]+))''',
    caseSensitive: false,
  ).firstMatch(header);

  if (match != null) {
    final quoted = match.group(1);
    if (quoted != null) {
      // 还原 \" \\ 等转义
      return quoted.replaceAllMapped(RegExp(r'\\(.)'), (m) => m.group(1)!);
    }
    final unquoted = match.group(2)?.trim();
    if (unquoted != null && unquoted.isNotEmpty) return unquoted;
  }

  return null;
}
