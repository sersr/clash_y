import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:server/server.dart' show clashSocket;
import 'package:server/tray_asset.dart';

abstract final class MacOSServiceProcess {
  static const _serviceLabel = 'com.aote.clashy.service';
  static const _helperRelativePath =
      'Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/'
      'packages/clash_service/bin/clashyService';
  static const _tunHelperRelativePath =
      'Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/'
      'packages/clash_service/bin/clashyTunHelper';

  static String get _bundlePath {
    final executable = Platform.resolvedExecutable;
    final marker = executable.indexOf('/Contents/MacOS/');
    if (marker < 0) {
      throw StateError('无法解析 App bundle 路径: $executable');
    }
    return executable.substring(0, marker);
  }

  static String get _helperPath => '$_bundlePath/$_helperRelativePath';
  static String get _tunHelperPath =>
      p.join(_bundlePath, _tunHelperRelativePath);
  static String get _trayPath =>
      p.join(p.dirname(_helperPath), clashTrayExecutableName);

  static String get _launchAgentPath =>
      p.join(_homeDirectory, 'Library', 'LaunchAgents', '$_serviceLabel.plist');

  static String get _homeDirectory {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError('HOME is not set for the macOS app process');
    }
    return home;
  }

  static Future<bool> isInstalled() async {
    try {
      await _validateBundleAssets();
      return true;
    } on FileSystemException {
      return false;
    } on StateError {
      return false;
    }
  }

  static Future<bool> isRunning() async {
    final domain = await _guiDomain();
    final status = await _launchAgentStatus(domain);
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
    final domain = await _guiDomain();
    final plistFile = File(_launchAgentPath);
    final expectedPlist = _launchAgentPlist(clashSocketPath);
    final plistIsCurrent =
        await plistFile.exists() &&
        await plistFile.readAsString() == expectedPlist;
    final status = await _launchAgentStatus(domain);
    final isLoaded = status != null;
    final isRunning =
        status != null && RegExp(r'\bstate = running\b').hasMatch(status);
    if (plistIsCurrent && isRunning && !forceRestart) {
      await _waitUntilRunning(domain);
      return;
    }

    await plistFile.parent.create(recursive: true);
    final temporaryPlist = File('$_launchAgentPath.tmp');
    await temporaryPlist.writeAsString(expectedPlist, flush: true);
    await temporaryPlist.rename(_launchAgentPath);

    await _runLaunchctlSetup(
      domain: domain,
      plistPath: _launchAgentPath,
      bootOutFirst: isLoaded,
    );
    await _waitUntilRunning(domain);
  }

  static String _launchAgentPlist(String clashSocketPath) =>
      '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$_serviceLabel</string>
  <key>ProgramArguments</key>
  <array>
    <string>${_xmlEscape(_helperPath)}</string>
    <string>--app</string>
    <string>${_xmlEscape(_bundlePath)}</string>
    <string>--service-socket</string>
    <string>${_xmlEscape(clashSocket)}</string>
    <string>--clash-socket</string>
    <string>${_xmlEscape(clashSocketPath)}</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${_xmlEscape(_bundlePath)}</string>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
</dict>
</plist>
''';

  static Future<String> _guiDomain() async {
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
    return 'gui/$uid';
  }

  static Future<String?> _launchAgentStatus(String domain) async {
    final result = await Process.run('/bin/launchctl', [
      'print',
      '$domain/$_serviceLabel',
    ]);
    if (result.exitCode != 0) return null;
    return result.stdout as String;
  }

  static Future<void> _runLaunchctl(List<String> arguments) async {
    final result = await Process.run('/bin/launchctl', arguments);
    if (result.exitCode != 0) {
      throw ProcessException(
        '/bin/launchctl',
        arguments,
        '${result.stderr}',
        result.exitCode,
      );
    }
  }

  static Future<void> _runLaunchctlSetup({
    required String domain,
    required String plistPath,
    required bool bootOutFirst,
  }) async {
    const script = '''
set -eu
domain="\$1"
label="\$2"
plist="\$3"
service_socket="\$5"
service_is_reachable() {
  printf '%s\\r\\n' 'GET /version HTTP/1.1' 'Host: localhost' 'Connection: close' '' |
    /usr/bin/nc -U "\$service_socket" -w 1 >/dev/null 2>&1
}
if [ "\$4" = "1" ]; then
  /bin/launchctl bootout "\$domain/\$label"
  attempts=0
  while /bin/launchctl print "\$domain/\$label" >/dev/null 2>&1 ||
    service_is_reachable
  do
    attempts=\$((attempts + 1))
    if [ "\$attempts" -ge 30 ]; then
      echo "Timed out waiting for clashyService to stop after bootout." >&2
      exit 1
    fi
    /bin/sleep 0.1
  done
fi
/bin/launchctl enable "\$domain/\$label"
/bin/launchctl bootstrap "\$domain" "\$plist"
''';
    final arguments = [
      '-c',
      script,
      'clashy-launch-agent',
      domain,
      _serviceLabel,
      plistPath,
      if (bootOutFirst) '1' else '0',
      clashSocket,
    ];
    final result = await Process.run('/bin/sh', arguments);
    if (result.exitCode != 0) {
      throw ProcessException(
        '/bin/sh',
        arguments,
        '${result.stderr}',
        result.exitCode,
      );
    }
  }

  static String _xmlEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static Future<void> _waitUntilRunning(String domain) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      final status = await _launchAgentStatus(domain);
      if (status != null &&
          RegExp(r'\bstate = running\b').hasMatch(status) &&
          await _isServiceSocketReady()) {
        return;
      }
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

  static Future<void> stop() async {
    final domain = await _guiDomain();
    await _stop(domain);
  }

  static Future<void> _stop(String domain) async {
    if (await _launchAgentStatus(domain) == null) return;
    await _runLaunchctl(['bootout', '$domain/$_serviceLabel']);
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      if (await _launchAgentStatus(domain) == null &&
          !await _isServiceSocketReady()) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw StateError('macOS clashyService did not stop after launchd bootout.');
  }

  static Future<void> uninstall() async {
    final domain = await _guiDomain();
    await _stop(domain);
    await _runLaunchctl(['disable', '$domain/$_serviceLabel']);
    final plistFile = File(_launchAgentPath);
    if (await plistFile.exists()) await plistFile.delete();
  }

  static Future<void> _validateBundleAssets() async {
    final bundlePath = p.normalize(p.absolute(_bundlePath));
    if (!p.basename(bundlePath).endsWith('.app')) {
      throw StateError('macOS service requires an app bundle');
    }

    final assets = [_helperPath, _tunHelperPath, _trayPath];
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
