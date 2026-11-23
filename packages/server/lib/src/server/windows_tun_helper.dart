import 'dart:io';
import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:server/clash_service_windows.dart' show runWindowsElevated;
import 'package:server/tray_asset.dart';

/// Windows 特权 TUN helper（以 LocalSystem 运行的 Windows 服务）。
abstract final class WindowsTunHelper {
  static const _serviceName = 'clashy_tun_helper';
  static const _readyTimeout = Duration(seconds: 10);
  static const _statePollInterval = Duration(milliseconds: 100);

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
      final script =
          'sc ${_serviceExists() ? 'config' : 'create'} $_serviceName '
          'binPath= $binPath start= auto\n'
          'sc description $_serviceName "Clashy TUN Helper"\n'
          'sc start $_serviceName\n';
      final code = await runWindowsElevated(script);
      if (code != 0 && code != 1223) {
        final query = Process.runSync('sc', ['query', _serviceName]);
        final config = Process.runSync('sc', ['qc', _serviceName]);
        throw StateError(
          'install Windows TUN helper failed (exit $code); '
          'sc query: ${query.stdout} ${query.stderr}; '
          'sc qc: ${config.stdout} ${config.stderr}',
        );
      }
      if (code == 1223) {
        throw StateError('install Windows TUN helper cancelled by user');
      }
    }

    await _waitUntilRunning();
  }

  static bool _serviceExists() {
    final result = Process.runSync('sc', ['query', _serviceName]);
    return result.exitCode == 0;
  }

  static bool _isRunning() {
    final result = Process.runSync('sc', ['query', _serviceName]);
    if (result.exitCode != 0) return false;
    final match = RegExp(r'STATE\s*:\s*(\d+)')
        .firstMatch(result.stdout as String);
    if (match == null) return false;
    final state = int.parse(match.group(1)!);
    return state == 2 || state == 4;
  }

  static Future<void> _waitUntilRunning() async {
    final deadline = DateTime.now().add(_readyTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final result = Process.runSync('sc', ['query', _serviceName]);
      final state = result.exitCode == 0
          ? RegExp(r'STATE\s*:\s*(\d+)')
                .firstMatch(result.stdout as String)
                ?.group(1)
          : null;
      if (state == '4') return;
      if (state == null || state == '1' || state == '3') {
        break;
      }
      await Future<void>.delayed(_statePollInterval);
    }
    final query = Process.runSync('sc', ['query', _serviceName]);
    throw StateError(
      'Windows TUN helper did not reach RUNNING: '
      '${query.stdout} ${query.stderr}',
    );
  }
}
