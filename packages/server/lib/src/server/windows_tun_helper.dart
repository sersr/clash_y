import 'dart:io';

import 'package:dart_ipc/dart_ipc.dart' show connect;
import 'package:path/path.dart' as p;
import 'package:server/clash_service_windows.dart' show runWindowsElevated;
import 'package:server/tray_asset.dart';

/// Windows 特权 TUN helper（以 LocalSystem 运行的 Windows 服务）。
abstract final class WindowsTunHelper {
  static const _serviceName = 'clashy_tun_helper';
  static const _readyTimeout = Duration(seconds: 10);

  static String get _helperPath => p.join(
        p.dirname(Platform.resolvedExecutable),
        clashTunHelperWindowsExecutableName,
      );

  static Future<void> ensureRegistered() async {
    final helperFile = File(_helperPath);
    if (!await helperFile.exists()) {
      throw StateError('Bundled Windows TUN helper is missing: $_helperPath');
    }

    if (!_serviceExists() || !_isRunning()) {
      final raw = _helperPath;
      final binPath = raw.contains(' ') ? '"\\"$raw\\""' : raw;
      final script = 'sc ${_serviceExists() ? 'config' : 'create'} $_serviceName '
          'binPath= $binPath start= auto\n'
          'sc description $_serviceName "Clashy TUN Helper"\n'
          'sc start $_serviceName\n';
      final code = await runWindowsElevated(script);
      if (code != 0 && code != 1223) {
        throw StateError('install Windows TUN helper failed (exit $code)');
      }
      if (code == 1223) {
        throw StateError('install Windows TUN helper cancelled by user');
      }
    }

    await _waitUntilPipeReady();
  }

  static bool _serviceExists() {
    final result = Process.runSync('sc', ['query', _serviceName]);
    return result.exitCode == 0;
  }

  static bool _isRunning() {
    final result = Process.runSync('sc', ['query', _serviceName]);
    if (result.exitCode != 0) return false;
    final match = RegExp(r'STATE\s*:\s*(\d+)').firstMatch(result.stdout as String);
    if (match == null) return false;
    final state = int.parse(match.group(1)!);
    return state == 2 || state == 4;
  }

  static Future<void> _waitUntilPipeReady() async {
    final deadline = DateTime.now().add(_readyTimeout);
    Object? lastError;
    while (true) {
      try {
        final socket = await connect(clashTunHelperPipePath)
            .timeout(const Duration(seconds: 2));
        socket.destroy();
        return;
      } catch (error) {
        lastError = error;
        if (DateTime.now().isAfter(deadline)) break;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    throw StateError(
      'Windows TUN helper pipe is not ready: $clashTunHelperPipePath ($lastError)',
    );
  }
}
