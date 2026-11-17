import 'dart:async';
import 'dart:io' as io;

import 'package:clash_service/clash_service.dart';
import 'package:common/common.dart';
import 'package:dio/dio.dart';
import 'package:file/file.dart';
import 'package:flutter_nop/flutter_nop.dart';
import 'package:nop/nop.dart';

final class ClashEvent with NopLifecycle {
  String get appConfigPath => G.appConfigPath;
  String get unixSocketPath => G.unixSocketPath;

  final ClashApi clashApi = .new(
    appConfigPath: G.appConfigPath,
    unixSocketPath: G.unixSocketPath,
  );

  Future<void> closeConnection(String id) => clashApi.closeConnection(id);

  Future<void> updateConfig(Profile profile) async {
    try {
      await syncConfigDotYaml(profile);
      await reloadCurrentConfig();
    } catch (e) {
      Log.i(e);
    }
  }

  Future<String> initConfig() async {
    return initConfigPath((profile) async => await reloadConfigs(profile));
  }

  FutureOr<void> reloadCurrentConfig() async {
    try {
      await initConfig();

      if (io.Platform.isAndroid && !ClashService.isVpnActive()) {
        final profile = BaseConfig.currentProfileData.value.toClashProfile(
          configYaml.parent.path,
        );
        final accepted = await ClashService.reloadCoreConfig(
          profile,
          controllerSocketPath: unixSocketPath,
        );
        if (!accepted) {
          Log.e('failed to request Android core configuration reload');
        }
        return;
      }

      if (io.Platform.isMacOS || io.Platform.isLinux || io.Platform.isWindows) {
        final response = await ClashServiceApi.reloadClashConfig();
        if (!response.success) {
          Log.e('reload Clash config failed: ${response.data}');
          return;
        }
        Log.i(response.data);
        return;
      }

      await clashApi.updateConfigPath(configYaml.path);
    } catch (e) {
      Log.e('reload Clash config failed: $e');
    }
  }

  File getFile(String url) {
    return G.getCacheFile(url);
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

  FutureOr<bool?> reloadConfigs(Profile profile, {bool refresh = false}) async {
    if (profile.url == null) return false;

    final res = await EventQueue.run(profile.id, () async {
      profile = _latestProfile(profile);
      final url = profile.url;
      if (url == null) return false;

      var file = getFile(url);
      var isError = false;
      final fileExists = await file.exists();
      if (!fileExists || profile.shouldUpdate() || refresh) {
        try {
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

          final disposition = responseFile.headers['content-disposition'];

          final fileName = _getFilenameFromContentDisposition(
            disposition?.join(''),
          );
          final userInfo = _parseSubscriptionUserInfo(info);

          final baseName = file.path;

          if (fileData != null) {
            final fileTemp = file.parent.childFile('$baseName.temp');
            if (!await fileTemp.exists()) {
              await fileTemp.create(recursive: true);
            }

            await fileTemp.writeAsString(fileData, flush: true);
            if (!await file.exists()) {
              await file.create(recursive: true);
            }
            await fileTemp.rename(file.path);
          }

          profile = profile.copyWith(
            rawName: fileName,
            upload: userInfo['upload'],
            download: userInfo['download'],
            total: userInfo['total'],
            expire: userInfo['expire'],
            updateTime: DateTime.now(),
            name: profile.name,
            updateInterval: profile.updateInterval,
            url: profile.url,
            scriptId: profile.scriptId,
          );

          if (profile.id case var id?) {
            BaseConfig.profiles.val.al[id] = profile;
          }
        } catch (e, s) {
          Log.e('$e,$s');
          isError = true;
        }
      }

      if (isError) {
        throw 'update url error.';
      }
      return true;
    });

    return res;
  }
}

String? _getFilenameFromContentDisposition(String? header) {
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

extension ProfileServiceX on Profile {
  /// Builds the service payload for this profile.
  ClashProfile toClashProfile(String configDir) {
    return ClashProfile(
      configDir: configDir,
      id: id,
      name: showName,
      url: url,
      updateInterval: updateInterval,
      updateTime: updateTime,
      script: SettingsHive.getScript(scriptId)?.script,
    );
  }
}
