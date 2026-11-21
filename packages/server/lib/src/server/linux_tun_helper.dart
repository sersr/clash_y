import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:server/tray_asset.dart';

/// Linux 特权 TUN helper（systemd unit，以 root 运行）。
abstract final class LinuxTunHelper {
  static const _label = 'clashy-tun-helper.service';
  static const _unitPath = '/etc/systemd/system/$_label';
  static const _readyTimeout = Duration(seconds: 10);

  static String get _helperPath => p.join(
        p.dirname(Platform.resolvedExecutable),
        clashTunHelperExecutableName,
      );

  static Future<void> ensureRegistered() async {
    final helperFile = File(_helperPath);
    if (!await helperFile.exists()) {
      throw StateError('Bundled Linux TUN helper is missing: $_helperPath');
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
    final expectedUnit = _unit(userId);
    final unitFile = File(_unitPath);
    final currentUnit = await unitFile.exists()
        ? await unitFile.readAsString()
        : '';
    final running = await _isRunning();

    if (currentUnit != expectedUnit || !running) {
      final exitCode = await _install(expectedUnit);
      if (exitCode != 0) {
        throw StateError(
          'install Linux TUN helper failed (pkexec exit $exitCode)',
        );
      }
    }

    await _waitUntilSocketReady();
  }

  static String _unit(String userId) {
    final exec = _helperPath.contains(' ')
        ? '"$_helperPath"'
        : _helperPath;
    return '''
[Unit]
Description=Clashy TUN Helper
After=network.target

[Service]
Type=simple
ExecStart=$exec --allowed-uid $userId
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
''';
  }

  static Future<bool> _isRunning() async {
    final result = await Process.run('systemctl', ['is-active', '--quiet', _label]);
    return result.exitCode == 0;
  }

  static Future<int> _install(String unit) async {
    final script = '''
set -e
mkdir -p /etc/systemd/system
cat > $_unitPath <<'EOF'
${unit}EOF
systemctl daemon-reload
systemctl enable $_label
systemctl restart $_label
''';
    final encoded = base64.encode(utf8.encode(script));
    final result = await Process.run('pkexec', [
      'sh',
      '-c',
      "echo '$encoded' | base64 -d | sh",
    ]);
    final error = (result.stderr as String).trim();
    if (result.exitCode != 0 && error.isNotEmpty) stderr.writeln(error);
    return result.exitCode;
  }

  static Future<void> _waitUntilSocketReady() async {
    final deadline = DateTime.now().add(_readyTimeout);
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
      'Linux TUN helper socket is not ready: $clashTunHelperSocketPath ($lastError)',
    );
  }
}
