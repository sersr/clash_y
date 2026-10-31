import 'dart:convert';
import 'dart:io';

import 'package:dart_ipc/dart_ipc.dart' show connect;
import 'package:server/server.dart' as service_server show clashSocket;

import '../tray_asset.dart';

/// 把 app bundle 内的状态栏程序路径交给 clashyService 保存并启动。
///
/// 状态栏图标必须运行在用户的 Aqua 会话里，root 的 LaunchDaemon 无法创建
/// NSStatusItem。service 负责在登录用户的 GUI 会话启动 tray 子进程。
abstract final class TrayInstaller {
  static String get serviceSocket => service_server.clashSocket;

  /// bundle 内源文件相对路径（相对于 .app 根目录）
  static const _trayRel = clashTrayBundleRelativePath;

  static String get _bundlePath {
    final exe = Platform.resolvedExecutable;
    final idx = exe.indexOf('/Contents/MacOS/');
    if (idx < 0) throw StateError('无法解析 App bundle 路径: $exe');
    return exe.substring(0, idx);
  }

  static String get _traySrc => '$_bundlePath/$_trayRel';

  /// 将 Tray 可执行文件路径和启动参数交给 clashyService 保存并启动。
  static Future<void> configure({required String clashSocket}) async {
    if (!Platform.isMacOS) return;

    await _sendRequest('/tray/configure', {
      'path': _traySrc,
      'serviceSocket': serviceSocket,
      'clashSocket': clashSocket,
      'appPath': _bundlePath,
    });
  }

  static Future<void> _sendRequest(
    String path,
    Map<String, Object?> data,
  ) async {
    final client = HttpClient()
      ..connectionFactory = (uri, proxyHost, proxyPort) async {
        final socketFuture = connect(serviceSocket);
        final socket = await socketFuture;
        return ConnectionTask.fromSocket(socketFuture, socket.destroy);
      }
      ..findProxy = (_) => 'DIRECT';
    try {
      SocketException? lastSocketError;
      for (var attempt = 0; attempt < 5; attempt++) {
        try {
          final request = await client.postUrl(
            Uri.parse('http://localhost$path'),
          );
          request.headers.set(
            HttpHeaders.contentTypeHeader,
            'application/json',
          );
          request.write(jsonEncode(data));
          final response = await request.close();
          final body = await response.transform(utf8.decoder).join();
          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw HttpException(
              'Tray server returned HTTP ${response.statusCode}: $body',
            );
          }
          final decoded = jsonDecode(body);
          if (decoded is! Map || decoded['code'] != 0) {
            throw StateError('Tray server rejected the request: $body');
          }
          return;
        } on SocketException catch (error) {
          lastSocketError = error;
          if (attempt < 4) {
            await Future<void>.delayed(const Duration(seconds: 2));
          }
        }
      }
      throw lastSocketError ??
          StateError('Unable to connect to the clashyService tray endpoint');
    } finally {
      client.close(force: true);
    }
  }
}
