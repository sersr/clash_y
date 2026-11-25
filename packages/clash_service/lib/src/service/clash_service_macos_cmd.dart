import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:server/server.dart' show clashSocket;
import 'package:server/tray_asset.dart';

/// macOS 服务安装/控制。
///
/// 守护进程跑在 system 域（`/Library/LaunchDaemons`、root），自己创建并配置
/// utun，不再有独立的 TUN helper；菜单栏托盘是用户 GUI 会话里的
/// `/Library/LaunchAgents` Agent，由 launchd 在每个登录用户里启动——daemon
/// 在 system 域没有 WindowServer 连接，画不出菜单栏。
abstract final class MacOSServiceProcess {
  static const _serviceLabel = 'com.aote.clashy.service';
  static const _trayLabel = 'com.aote.clashy.tray';

  static const _daemonPlistPath =
      '/Library/LaunchDaemons/com.aote.clashy.service.plist';
  static const _trayPlistPath =
      '/Library/LaunchAgents/com.aote.clashy.tray.plist';

  /// 服务二进制由 root 拥有的副本；不直接执行 app bundle 里的文件，避免用户
  /// 替换 bundle 内容后拿到 root 权限。
  static const _installedServicePath =
      '/Library/PrivilegedHelperTools/com.aote.clashy.service';

  static const _serviceRelativePath =
      'Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/'
      'packages/clash_service/bin/clashyService';

  static String get _bundlePath {
    final executable = Platform.resolvedExecutable;
    final marker = executable.indexOf('/Contents/MacOS/');
    if (marker < 0) {
      throw StateError('无法解析 App bundle 路径: $executable');
    }
    return executable.substring(0, marker);
  }

  static String get _servicePath => p.join(_bundlePath, _serviceRelativePath);

  static String get _trayPath =>
      p.join(p.dirname(_servicePath), clashTrayExecutableName);

  static Future<bool> isInstalled() async {
    try {
      await _validateBundleAssets();
    } on FileSystemException {
      return false;
    } on StateError {
      return false;
    }
    return File(_daemonPlistPath).existsSync() &&
        File(_installedServicePath).existsSync();
  }

  static Future<bool> isRunning() async {
    final status = await _launchctlPrint('system/$_serviceLabel');
    return status != null && RegExp(r'\bstate = running\b').hasMatch(status);
  }

  static Future<bool> hasOtherVpnConnection({
    bool checkTunnelRoutes = true,
  }) async {
    final connections = await Process.run('/usr/sbin/scutil', ['--nc', 'list']);
    if (connections.exitCode != 0) {
      throw ProcessException(
        '/usr/sbin/scutil',
        const ['--nc', 'list'],
        '${connections.stderr}',
        connections.exitCode,
      );
    }
    if (RegExp(
      r'\(\s*Connected\s*\)',
      caseSensitive: false,
    ).hasMatch(connections.stdout as String)) {
      return true;
    }
    if (!checkTunnelRoutes) return false;

    final routes = await Process.run('/usr/sbin/netstat', [
      '-rn',
      '-f',
      'inet',
    ]);
    if (routes.exitCode != 0) {
      throw ProcessException(
        '/usr/sbin/netstat',
        const ['-rn', '-f', 'inet'],
        '${routes.stderr}',
        routes.exitCode,
      );
    }

    return (routes.stdout as String).split('\n').any((line) {
      final fields = line.trim().split(RegExp(r'\s+'));
      return fields.length >= 4 &&
          fields.any((field) => RegExp(r'^utun\d+$').hasMatch(field));
    });
  }

  static Future<void> install({
    required String clashSocketPath,
    bool forceRestart = false,
  }) async {
    await _validateBundleAssets();
    final uid = await _currentUid();
    final expectedDaemon = _daemonPlist(clashSocketPath, uid);
    final expectedTray = _trayPlist(clashSocketPath);
    final currentDaemon = await _readFileIfExists(_daemonPlistPath);
    final currentTray = await _readFileIfExists(_trayPlistPath);
    final bundledHash = await _sha256(_servicePath);
    final installedHash = await _sha256(_installedServicePath);
    final upToDate =
        currentDaemon == expectedDaemon &&
        currentTray == expectedTray &&
        bundledHash != null &&
        bundledHash == installedHash &&
        await isRunning();

    if (upToDate && !forceRestart) {
      await _waitUntilRunning();
      return;
    }

    await _runElevated(
      _installScript(
        uid: uid,
        daemonPlist: expectedDaemon,
        trayPlist: expectedTray,
      ),
    );
    await _waitUntilRunning();
  }

  /// 安装脚本：拷贝 root 拥有的服务副本、写两份 plist，再分别 bootstrap 到
  /// `system` 与当前用户的 `gui/<uid>` 域。
  static String _installScript({
    required int uid,
    required String daemonPlist,
    required String trayPlist,
  }) {
    const daemonPlistTemp = '/tmp/clashy-service.plist';
    const trayPlistTemp = '/tmp/clashy-tray.plist';
    return '''
set -eu
/usr/bin/install -o root -g wheel -m 755 ${_shellQuote(_servicePath)} ${_shellQuote(_installedServicePath)}
/bin/mkdir -p /Library/LaunchDaemons /Library/LaunchAgents
printf '%s' ${_shellQuote(daemonPlist)} > ${_shellQuote(daemonPlistTemp)}
/usr/sbin/chown root:wheel ${_shellQuote(daemonPlistTemp)}
/bin/chmod 644 ${_shellQuote(daemonPlistTemp)}
/bin/mv -f ${_shellQuote(daemonPlistTemp)} ${_shellQuote(_daemonPlistPath)}
printf '%s' ${_shellQuote(trayPlist)} > ${_shellQuote(trayPlistTemp)}
/usr/sbin/chown root:wheel ${_shellQuote(trayPlistTemp)}
/bin/chmod 644 ${_shellQuote(trayPlistTemp)}
/bin/mv -f ${_shellQuote(trayPlistTemp)} ${_shellQuote(_trayPlistPath)}
/bin/launchctl bootout system/$_serviceLabel >/dev/null 2>&1 || true
/bin/launchctl enable system/$_serviceLabel
/bin/launchctl bootstrap system ${_shellQuote(_daemonPlistPath)}
/bin/launchctl bootout gui/$uid/$_trayLabel >/dev/null 2>&1 || true
/bin/launchctl enable gui/$uid/$_trayLabel
/bin/launchctl bootstrap gui/$uid ${_shellQuote(_trayPlistPath)}
''';
  }

  /// 守护进程以 root 运行，控制面只对安装它的那个桌面用户（以及 root）放行：
  /// `--allowed-uid` 让服务在 accept 时用 peer credentials 校验客户端 uid。
  static String _daemonPlist(String clashSocketPath, int uid) =>
      '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$_serviceLabel</string>
  <key>ProgramArguments</key>
  <array>
    <string>${_xmlEscape(_installedServicePath)}</string>
    <string>--service-socket</string>
    <string>${_xmlEscape(clashSocket)}</string>
    <string>--clash-socket</string>
    <string>${_xmlEscape(clashSocketPath)}</string>
    <string>--allowed-uid</string>
    <string>$uid</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
</dict>
</plist>
''';

  static String _trayPlist(String clashSocketPath) =>
      '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$_trayLabel</string>
  <key>ProgramArguments</key>
  <array>
    <string>${_xmlEscape(_trayPath)}</string>
    <string>--app</string>
    <string>${_xmlEscape(_bundlePath)}</string>
    <string>--service-socket</string>
    <string>${_xmlEscape(clashSocket)}</string>
    <string>--clash-socket</string>
    <string>${_xmlEscape(clashSocketPath)}</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${_xmlEscape(_bundlePath)}</string>
  <key>LimitLoadToSessionType</key>
  <string>Aqua</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
</dict>
</plist>
''';

  static Future<void> stop() async {
    if (!await isRunning()) return;
    await _runElevated('''
set -eu
/bin/launchctl bootout system/$_serviceLabel >/dev/null 2>&1 || true
''');
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      if (!await isRunning() && !await _isServiceSocketReady()) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw StateError('macOS clashyService did not stop after launchd bootout.');
  }

  static Future<void> uninstall() async {
    final uid = await _currentUid();
    await _runElevated('''
set -eu
/bin/launchctl bootout system/$_serviceLabel >/dev/null 2>&1 || true
/bin/launchctl disable system/$_serviceLabel >/dev/null 2>&1 || true
/bin/launchctl bootout gui/$uid/$_trayLabel >/dev/null 2>&1 || true
/bin/launchctl disable gui/$uid/$_trayLabel >/dev/null 2>&1 || true
/bin/rm -f ${_shellQuote(_daemonPlistPath)} ${_shellQuote(_trayPlistPath)} ${_shellQuote(_installedServicePath)}
''');
  }

  static Future<int> _currentUid() async {
    final result = await Process.run('/usr/bin/id', ['-u']);
    if (result.exitCode != 0) {
      throw ProcessException(
        '/usr/bin/id',
        const ['-u'],
        '${result.stderr}',
        result.exitCode,
      );
    }
    final uid = (result.stdout as String).trim();
    if (!RegExp(r'^[1-9]\d*$').hasMatch(uid)) {
      throw FormatException('Unexpected user ID for LaunchAgent: $uid');
    }
    return int.parse(uid);
  }

  static Future<String?> _launchctlPrint(String domain) async {
    final result = await Process.run('/bin/launchctl', ['print', domain]);
    if (result.exitCode != 0) return null;
    return result.stdout as String;
  }

  /// 通过 osascript 的 administrator 授权执行脚本，与其他平台的提权入口一致。
  static Future<void> _runElevated(String script) async {
    final encoded = base64Encode(utf8.encode(script));
    final command = "printf '%s' '$encoded' | /usr/bin/base64 -D | /bin/sh";
    final appleScript =
        'do shell script "${command.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}" '
        'with administrator privileges';
    final result = await Process.run('/usr/bin/osascript', ['-e', appleScript]);
    if (result.exitCode != 0) {
      throw ProcessException(
        '/usr/bin/osascript',
        const ['-e', '<installer script>'],
        '${result.stderr}',
        result.exitCode,
      );
    }
  }

  static String _shellQuote(String value) =>
      "'${value.replaceAll("'", "'\"'\"'")}'";

  static Future<String?> _readFileIfExists(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  static Future<String?> _sha256(String path) async {
    if (!File(path).existsSync()) return null;
    final result = await Process.run('/usr/bin/shasum', ['-a', '256', path]);
    if (result.exitCode != 0) {
      throw ProcessException(
        '/usr/bin/shasum',
        ['-a', '256', path],
        '${result.stderr}',
        result.exitCode,
      );
    }
    return (result.stdout as String).split(' ').first;
  }

  static String _xmlEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static Future<void> _waitUntilRunning() async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      if (await isRunning() && await _isServiceSocketReady()) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw StateError('macOS clashyService did not become ready.');
  }

  static Future<bool> _isServiceSocketReady() async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress(clashSocket, type: InternetAddressType.unix),
        0,
        timeout: const Duration(milliseconds: 500),
      );
      return true;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  static Future<void> _validateBundleAssets() async {
    final bundlePath = p.normalize(p.absolute(_bundlePath));
    if (!p.basename(bundlePath).endsWith('.app')) {
      throw StateError('macOS service requires an app bundle');
    }

    final assets = [_servicePath, _trayPath];
    final checkedPaths = <String>{};
    for (final assetPath in assets) {
      final path = p.normalize(p.absolute(assetPath));
      if (!p.isWithin(bundlePath, path)) {
        throw StateError(
          'macOS service asset is outside the app bundle: $path',
        );
      }

      for (final current in _pathComponents(path)) {
        final type = await FileSystemEntity.type(current, followLinks: false);
        if (type == FileSystemEntityType.link ||
            type == FileSystemEntityType.notFound) {
          throw StateError(
            'macOS service path is missing or contains a symlink: $current',
          );
        }
        checkedPaths.add(current);
      }

      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw StateError('macOS service asset is missing: $path');
      }
    }

    final modes = await _readModes(checkedPaths.toList());
    for (final assetPath in assets) {
      final path = p.normalize(p.absolute(assetPath));
      for (final current in _pathComponents(path)) {
        final mode = modes[current];
        if (mode == null) {
          throw StateError('Missing permissions for service path: $current');
        }
        final insideBundle =
            current == bundlePath || p.isWithin(bundlePath, current);
        if (insideBundle && (mode & 0x12) != 0) {
          throw StateError(
            'macOS service path must not be writable by other users: $current',
          );
        }
        if (current == path && (mode & 0x40) == 0) {
          throw StateError('macOS service executable is not executable: $path');
        }
      }
    }
  }

  static List<String> _pathComponents(String path) {
    var current = '/';
    return p.relative(path, from: '/').split('/').map((component) {
      current = p.join(current, component);
      return current;
    }).toList();
  }

  static Future<Map<String, int>> _readModes(List<String> paths) async {
    final arguments = ['-f', '%Lp', ...paths];
    final result = await Process.run('/usr/bin/stat', arguments);
    if (result.exitCode != 0) {
      throw ProcessException(
        '/usr/bin/stat',
        arguments,
        '${result.stderr}',
        result.exitCode,
      );
    }
    final permissions = (result.stdout as String).trim().split('\n');
    if (permissions.length != paths.length) {
      throw FormatException(
        'Unexpected stat output for ${paths.length} paths: ${result.stdout}',
      );
    }
    return {
      for (var index = 0; index < paths.length; index++)
        paths[index]: _parseMode(paths[index], permissions[index]),
    };
  }

  static int _parseMode(String path, String permissions) {
    if (!RegExp(r'^[0-7]{3,4}$').hasMatch(permissions)) {
      throw FormatException('Unexpected stat output for $path: $permissions');
    }
    return int.parse(permissions, radix: 8);
  }
}
