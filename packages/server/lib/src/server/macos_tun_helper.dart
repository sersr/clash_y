import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:server/tray_asset.dart';

abstract final class MacOSTunHelper {
  static const _label = 'com.aote.clashy.tun-helper';
  static const _plistPath =
      '/Library/LaunchDaemons/com.aote.clashy.tun-helper.plist';
  static const _installPath =
      '/Library/PrivilegedHelperTools/com.aote.clashy.tun-helper';

  static const _socketReadyTimeout = Duration(seconds: 10);

  static Future<void> ensureRegistered() async {
    final executablePath = p.normalize(p.absolute(Platform.resolvedExecutable));
    final helperPath = p.join(p.dirname(executablePath), 'clashyTunHelper');
    if (!await File(helperPath).exists()) {
      throw StateError('Bundled macOS TUN helper is missing: $helperPath');
    }

    final userIdResult = await Process.run('/usr/bin/id', ['-u']);
    if (userIdResult.exitCode != 0) {
      throw ProcessException(
        '/usr/bin/id',
        const ['-u'],
        '${userIdResult.stderr}',
        userIdResult.exitCode,
      );
    }
    final userId = (userIdResult.stdout as String).trim();
    if (!RegExp(r'^\d+$').hasMatch(userId) || userId == '0') {
      throw FormatException('Unexpected user ID: $userId');
    }

    final bundledHash = await _fileHash(helperPath);
    final installedHash = await _fileHash(_installPath);
    final expectedPlist = _launchDaemonPlist(userId);
    final plistFile = File(_plistPath);
    final plistContent = await plistFile.exists()
        ? await plistFile.readAsString()
        : '';
    final needsInstall =
        bundledHash != installedHash ||
        plistContent != expectedPlist ||
        !(await _isLaunchdRunning());
    if (needsInstall) {
      await _install(helperPath, expectedPlist);
      await _waitUntilReady();
    }

    // launchd 报 running 只说明进程拉起来了；helper listen 好 socket 之前
    // mihomo 一连就失败，所以还要等 socket 可用。
    await _waitUntilSocketReady();
  }

  static Future<bool> _isLaunchdRunning() async {
    final status = await _launchdStatus();
    return status.exitCode == 0 &&
        RegExp(r'\bstate = running\b').hasMatch(status.stdout as String);
  }

  /// 等待 helper 把 unix socket listen 起来；能连上才代表可以请求 TUN。
  static Future<void> _waitUntilSocketReady() async {
    final deadline = DateTime.now().add(_socketReadyTimeout);
    Object? lastError;
    while (true) {
      try {
        final socket = await Socket.connect(
          InternetAddress(clashTunHelperSocketPath, type: InternetAddressType.unix),
          0,
        ).timeout(const Duration(seconds: 2));
        socket.destroy();
        return;
      } catch (error) {
        lastError = error;
        if (DateTime.now().isAfter(deadline)) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    throw StateError(
      'macOS TUN helper socket is not ready: $clashTunHelperSocketPath ($lastError)',
    );
  }

  static Future<void> _install(String helperPath, String plist) async {
    final plistBase64 = base64.encode(utf8.encode(plist));
    final quotedHelperPath = _shellQuote(helperPath);
    final quotedInstallPath = _shellQuote(_installPath);
    final script =
        '''
if /bin/launchctl print "system/$_label" >/dev/null 2>&1; then
  /bin/launchctl bootout "system/$_label" || exit \$?
fi
/usr/bin/install -o root -g wheel -m 755 $quotedHelperPath $quotedInstallPath || exit \$?
printf '%s' '$plistBase64' | /usr/bin/base64 -D > '$_plistPath' || exit \$?
/usr/sbin/chown root:wheel '$_plistPath' || exit \$?
/bin/chmod 644 '$_plistPath' || exit \$?
/bin/launchctl bootstrap system '$_plistPath' || exit \$?
/bin/launchctl enable "system/$_label" || exit \$?
''';
    final encodedScript = base64.encode(utf8.encode(script));
    final appleScript =
        "do shell script \"printf '%s' '$encodedScript' | /usr/bin/base64 -D | /bin/bash\" with administrator privileges";
    final result = await Process.run('/usr/bin/osascript', ['-e', appleScript]);
    if (result.exitCode != 0) {
      throw ProcessException(
        '/usr/bin/osascript',
        ['-e', appleScript],
        '${result.stderr}${result.stdout}',
        result.exitCode,
      );
    }
  }

  static String _launchDaemonPlist(String userId) =>
      '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$_label</string>
  <key>ProgramArguments</key>
  <array>
    <string>$_installPath</string>
    <string>--allowed-uid</string>
    <string>$userId</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
</dict>
</plist>
''';

  static Future<String?> _fileHash(String path) async {
    if (!await File(path).exists()) return null;
    final result = await Process.run('/usr/bin/shasum', ['-a', '256', path]);
    if (result.exitCode != 0) {
      throw ProcessException(
        '/usr/bin/shasum',
        ['-a', '256', path],
        '${result.stderr}',
        result.exitCode,
      );
    }
    return (result.stdout as String).split(RegExp(r'\s+')).first;
  }

  static Future<ProcessResult> _launchdStatus() =>
      Process.run('/bin/launchctl', ['print', 'system/$_label']);

  static Future<void> _waitUntilReady() async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (DateTime.now().isBefore(deadline)) {
      final result = await _launchdStatus();
      if (result.exitCode == 0 &&
          RegExp(r'\bstate = running\b').hasMatch(result.stdout as String)) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('macOS privileged TUN helper did not become ready.');
  }

  static String _shellQuote(String value) =>
      "'${value.replaceAll("'", "'\\''")}'";
}
