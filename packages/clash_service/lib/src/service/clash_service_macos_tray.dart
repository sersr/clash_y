import 'dart:io';

import 'package:server/server.dart' as service_server show clashSocket;

import '../tray_asset.dart';

/// 保存状态栏程序配置，并从当前用户的图形会话启动 Tray。
abstract final class TrayInstaller {
  static const _launchAgentLabel = 'com.aote.clashy.tray';

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

  static String get _launchAgentPath {
    final home = Platform.environment['HOME'];
    if (home == null) throw StateError('无法获取当前用户的 HOME 目录');
    return '$home/Library/LaunchAgents/$_launchAgentLabel.plist';
  }

  /// 确保 Tray 的当前用户 LaunchAgent 已配置并运行。
  static Future<void> ensureConfigured({required String clashSocket}) async {
    if (!Platform.isMacOS) return;

    final appPath = _bundlePath;
    final trayPath = _traySrc;
    final arguments = [
      trayPath,
      '--app',
      appPath,
      '--service-socket',
      serviceSocket,
      '--clash-socket',
      clashSocket,
    ];
    final contents = _launchAgentPlist(arguments);
    final plist = File(_launchAgentPath);
    await plist.parent.create(recursive: true);

    final userId = await _currentUserId();
    final domain = 'gui/$userId';
    final service = '$domain/$_launchAgentLabel';
    final existing = await Process.run('launchctl', ['print', service]);
    final isConfigured =
        await plist.exists() && await plist.readAsString() == contents;

    if (isConfigured && existing.exitCode == 0) {
      if ((existing.stdout as String).contains('state = running')) return;
      await _runLaunchctl(['kickstart', service]);
      return;
    }

    if (!isConfigured) {
      await plist.writeAsString(contents, flush: true);
    }
    if (existing.exitCode == 0) {
      await _runLaunchctl(['bootout', service]);
    }
    await _runLaunchctl(['bootstrap', domain, plist.path]);
  }

  static Future<String> _currentUserId() async {
    final result = await Process.run('id', ['-u']);
    if (result.exitCode != 0) {
      throw ProcessException('id', ['-u'], '${result.stderr}', result.exitCode);
    }
    return (result.stdout as String).trim();
  }

  static String _launchAgentPlist(List<String> arguments) {
    final programArguments = arguments
        .map((argument) => '<string>${_escapeXml(argument)}</string>')
        .join();
    return '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$_launchAgentLabel</string>
  <key>ProgramArguments</key>
  <array>$programArguments</array>
  <key>RunAtLoad</key>
  <true/>
  <key>LimitLoadToSessionType</key>
  <string>Aqua</string>
</dict>
</plist>
''';
  }

  static String _escapeXml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static Future<void> _runLaunchctl(List<String> arguments) async {
    final result = await Process.run('launchctl', arguments);
    if (result.exitCode != 0) {
      throw ProcessException(
        'launchctl',
        arguments,
        '${result.stderr}',
        result.exitCode,
      );
    }
  }
}
