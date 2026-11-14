import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:clash_core/clash_core.dart';
import 'package:ffi/ffi.dart';
import 'package:nop/nop.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'config_overrides.dart';
import 'models/models.dart';

final _clashQueue = TaskQueue();
final _stateQueue = TaskQueue();

abstract final class ClashProcess {
  static const _wakeNetworkSettleDelay = Duration(seconds: 5);
  static const _stateFilePath =
      '/Library/Application Support/Clashy/clash-state.json';
  static String? _wakeMonitorLibraryPath;

  static final _stateFile = File(_stateFilePath);
  static ReceivePort? _wakeEvents;
  static StreamSubscription<dynamic>? _wakeSubscription;
  static Isolate? _wakeMonitor;
  static bool _recoveringTunAfterWake = false;
  static String? _tunInterface;

  static ClashProfile? _profile;
  static Timer? _profileTimer;
  static var _vpnEnabled = false;

  static void configureWakeMonitorLibraryPath(String path) {
    if (path.isEmpty) {
      throw ArgumentError.value(path, 'path', 'cannot be empty');
    }
    _wakeMonitorLibraryPath = path;
  }

  static Future<void> restorePersistedClash() async {
    if (!Platform.isMacOS || !await _stateFile.exists()) return;

    try {
      final state = jsonDecode(await _stateFile.readAsString());
      if (state is! Map) {
        Log.e('saved Clash state is invalid');
        return;
      }

      final profile = switch (state['profile']) {
        final Map<dynamic, dynamic> json => ClashProfile.fromJson(json),
        _ => null,
      };
      final configDir = switch (state['configDir']) {
        final String dir when dir.isNotEmpty => dir,
        _ => profile?.configDir,
      };
      final vpnEnabled = state['vpnEnabled'] is bool
          ? state['vpnEnabled'] as bool
          : true;
      if (configDir == null || configDir.isEmpty) {
        Log.e('saved Clash state has no configuration directory');
        return;
      }

      Log.w('restoring Clash from saved state');
      final error = vpnEnabled
          ? await run(configDir)
          : await runCoreOnly(configDir);
      if (error != null) {
        Log.e('restore Clash from saved state failed: $error');
        return;
      }
      if (profile != null) {
        _setProfile(profile);
      }
    } catch (e) {
      Log.e('restore Clash from saved state failed: $e');
    }
  }

  static Future<void> _persistState(ClashProfile profile) async {
    if (!Platform.isMacOS) return;

    await _stateQueue.run(() async {
      final temporaryFile = File('$_stateFilePath.tmp');
      await temporaryFile.create(recursive: true);
      await temporaryFile.writeAsString(
        jsonEncode({
          'configDir': profile.configDir,
          'profile': profile.toJson(),
          'vpnEnabled': _vpnEnabled,
        }),
        flush: true,
      );
      await temporaryFile.rename(_stateFilePath);
    });
  }

  static Future<void> _clearPersistedState() async {
    if (!Platform.isMacOS) return;
    await _stateQueue.run(() async {
      if (await _stateFile.exists()) {
        await _stateFile.delete();
      }
    });
  }

  static Future<void> initialize() async {
    try {
      await startMacOSWakeMonitor();
    } catch (e) {
      Log.e('start macOS wake monitor failed: $e');
    }
    await restorePersistedClash();
  }

  static Future<void> startMacOSWakeMonitor() async {
    if (!Platform.isMacOS ||
        _wakeMonitor != null ||
        _wakeEvents != null ||
        _wakeSubscription != null) {
      return;
    }
    final libraryPath = _wakeMonitorLibraryPath;
    if (libraryPath == null) {
      throw StateError('wake monitor library path has not been configured');
    }
    if (!await File(libraryPath).exists()) {
      throw StateError('wake monitor library is missing: $libraryPath');
    }

    final events = ReceivePort();
    _wakeEvents = events;
    _wakeSubscription = events.listen((message) {
      if (message == 'wake') {
        unawaited(_recoverTunAfterWake());
      } else if (message is Map && message['error'] is String) {
        Log.e('macOS wake monitor failed: ${message['error']}');
      }
    });
    _wakeMonitor = await Isolate.spawn(_watchMacOSWake, (
      events.sendPort,
      libraryPath,
    ), debugName: 'clashy-macos-wake-monitor');
  }

  @pragma('vm:entry-point')
  static void _watchMacOSWake((SendPort, String) args) {
    final (sendPort, libraryPath) = args;
    try {
      final library = DynamicLibrary.open(libraryPath);
      final start = library.lookupFunction<Int32 Function(), int Function()>(
        'clashy_wake_monitor_start',
      );
      final wait = library.lookupFunction<Int32 Function(), int Function()>(
        'clashy_wake_monitor_wait',
      );
      if (start() != 0) {
        throw StateError('IOKit power notification registration failed');
      }

      sendPort.send('ready');
      while (true) {
        if (wait() != 0) {
          throw StateError('IOKit wake notification wait failed');
        }
        sendPort.send('wake');
      }
    } catch (e) {
      sendPort.send({'error': '$e'});
    }
  }

  static Future<void> _recoverTunAfterWake() async {
    final configDir = _clashKey;
    if (_recoveringTunAfterWake ||
        !_started ||
        !_vpnEnabled ||
        configDir == null) {
      return;
    }

    _recoveringTunAfterWake = true;
    try {
      final configFile = File('$configDir${Platform.pathSeparator}config.yaml');
      final config = loadYaml(await configFile.readAsString());
      final tun = config is Map ? config['tun'] : null;
      if (tun is! Map || tun['enable'] != true) return;

      if (await _isTunHealthy()) {
        Log.i('TUN is healthy after system wake; no restart needed');
        return;
      }

      Log.w('system wake detected; TUN is unavailable, restoring it');
      await Future<void>.delayed(_wakeNetworkSettleDelay);
      await _clashQueue.run(() async {
        if (!_started || _clashKey != configDir) return;

        final vpnEnabled = _vpnEnabled;
        final stopError = await _stopSingle();
        if (stopError != null) {
          Log.e('restore TUN after wake: stop failed: $stopError');
          return;
        }

        final startError = await _runSingle(configDir, vpnEnabled: vpnEnabled);
        if (startError != null) {
          Log.e('restore TUN after wake: start failed: $startError');
          return;
        }

        Log.w('TUN restored after system wake');
      });
    } catch (e) {
      Log.e('restore TUN after wake failed: $e');
    } finally {
      _recoveringTunAfterWake = false;
    }
  }

  static Future<bool> _isTunHealthy() async {
    final tunInterface = _tunInterface;
    if (tunInterface == null) {
      Log.w('unable to verify TUN interface; skipping wake recovery');
      return true;
    }

    final result = await Process.run('/sbin/ifconfig', [tunInterface]);
    if (result.exitCode != 0) return false;

    final output = result.stdout as String;
    final firstLine = output.split('\n').firstOrNull ?? '';
    return RegExp(r'flags=\d+<[^>]*\bUP\b').hasMatch(firstLine);
  }

  static bool get started => _started;

  static bool get vpnEnabled => _vpnEnabled;

  static Future<String?> run(String configDir) async {
    return _clashQueue.run(() => _runSingle(configDir, vpnEnabled: true));
  }

  static Future<String?> runCoreOnly(String configDir) async {
    return _clashQueue.run(() => _runSingle(configDir, vpnEnabled: false));
  }

  static Future<void> setProfile(ClashProfile profile) => _setProfile(profile);

  static Future<void> updateProfile(ClashProfile profile) async {
    final current = _profile;
    await _setProfile(
      profile.configDir.isEmpty && current != null
          ? profile.copyWith(configDir: current.configDir)
          : profile,
    );
  }

  static Future<String?> stopVpn() async {
    final configDir = _clashKey;
    if (!_started || configDir == null) {
      _vpnEnabled = false;
      return null;
    }

    final error = await runCoreOnly(configDir);
    if (error != null) return error;
    final profile = _profile;
    if (profile != null) await _persistState(profile);
    return null;
  }

  static Future<String?> reloadConfig() async {
    return _clashQueue.run(() async {
      if (!_started || _clashKey == null) {
        return 'Clash core is not running';
      }

      final configDir = _clashKey!;
      final vpnEnabled = _vpnEnabled;
      final stopError = await _stopSingle();
      if (stopError != null) return stopError;
      return _runSingle(configDir, vpnEnabled: vpnEnabled);
    });
  }

  static Future<String?> stop() async {
    final err = await _clashQueue.run(_stopSingle);
    if (err case var err? when err.isNotEmpty) return err;
    _profileTimer?.cancel();
    _profileTimer = null;
    _profile = null;
    _vpnEnabled = false;
    await _clearPersistedState();
    return null;
  }

  static Future<void> _setProfile(ClashProfile profile) async {
    _profile = profile;
    _scheduleProfileUpdate();
    await _persistState(profile);
  }

  static void _scheduleProfileUpdate() {
    _profileTimer?.cancel();
    _profileTimer = null;

    final delay = _profile?.nextUpdateDelay();
    if (delay == null) return;
    _profileTimer = Timer(delay, () => unawaited(_updateProfile()));
  }

  static Future<void> _updateProfile() async {
    final profile = _profile;
    if (profile == null || !profile.canAutoUpdate) {
      _scheduleProfileUpdate();
      return;
    }

    try {
      final error = await _refreshConfig(profile);
      // Stopped or switched while the config was downloading.
      if (!identical(_profile, profile)) return;
      if (error != null) {
        Log.e('profile update failed: $error');
      } else {
        await _setProfile(profile.copyWith(updateTime: DateTime.now()));
        Log.i('profile updated: ${profile.name ?? profile.id ?? profile.url}');
        return;
      }
    } catch (e) {
      Log.e('profile update failed: $e');
    }
    if (!identical(_profile, profile)) return;
    // Retry after a full interval instead of hammering an unreachable server.
    _profile = profile.copyWith(updateTime: DateTime.now());
    _scheduleProfileUpdate();
  }

  /// Downloads the subscription and restarts the core with the merged config.
  static Future<String?> _refreshConfig(ClashProfile profile) async {
    final url = profile.url;
    if (url == null || url.isEmpty) return 'profile url is empty';

    final configFile = File(p.join(profile.configDir, 'config.yaml'));
    if (!await configFile.exists()) {
      return 'missing config file: ${configFile.path}';
    }

    final current = await configFile.readAsString();
    final downloaded = await _downloadConfig(url);
    final merged = applyConfigOverrides(downloaded, current);

    final backupPath = '${configFile.path}.bak';
    final backup = File(backupPath);
    await configFile.copy(backupPath);
    await _writeConfig(configFile, merged);

    var vpnEnabled = false;
    final error = await _clashQueue.run(() async {
      if (!_started || !identical(_profile, profile)) return null;
      vpnEnabled = _vpnEnabled;
      final stopError = await _stopSingle();
      if (stopError != null) return stopError;
      return _runSingle(profile.configDir, vpnEnabled: vpnEnabled);
    });
    if (!identical(_profile, profile)) return null;
    if (error == null) {
      await backup.delete();
      return null;
    }

    Log.e('restart with the updated config failed: $error');
    await _writeConfig(configFile, await backup.readAsString());
    await backup.delete();
    final restoreError = await _clashQueue.run(() async {
      if (!identical(_profile, profile)) return null;
      await _stopSingle();
      return _runSingle(profile.configDir, vpnEnabled: vpnEnabled);
    });
    if (restoreError != null) {
      Log.e('restore previous config failed: $restoreError');
    }
    return error;
  }

  static Future<String> _downloadConfig(String url) async {
    final uri = Uri.parse(url);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'clash/mihomo');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'unexpected status ${response.statusCode}',
          uri: uri,
        );
      }
      if (body.trim().isEmpty) {
        throw HttpException('empty response', uri: uri);
      }
      return body;
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> _writeConfig(File file, String content) async {
    await file.writeAsString(content, flush: true);
  }

  static String? _clashKey;
  static var _started = false;
  static Future<String?> _runSingle(
    String configDir, {
    required bool vpnEnabled,
  }) async {
    if (_clashKey == configDir) {
      if (_started && _vpnEnabled == vpnEnabled) {
        return null;
      }
    }

    final interfacesBeforeStart = Platform.isMacOS
        ? await _listTunInterfaces()
        : const <String>{};

    String? err;
    _started = false;
    using((arena) {
      try {
        final nativeConfigDir = configDir
            .toNativeUtf8(allocator: arena)
            .cast<Char>();
        final res = vpnEnabled
            ? start(nativeConfigDir)
            : startTun(nativeConfigDir, 0);
        if (res != nullptr) {
          final error = res.cast<Utf8>().toDartString();
          if (error.isNotEmpty) {
            err = error;
            Log.e('start Error: $error');
          }
          freeString(res);
          _started = false;
        } else {
          _started = true;
        }
      } catch (e) {
        Log.e('start error: $e');
        err = e.toString();
      }
    });

    _clashKey = configDir;
    _vpnEnabled = err == null && _started && vpnEnabled;
    if (err == null && _started && vpnEnabled && Platform.isMacOS) {
      final interfacesAfterStart = await _listTunInterfaces();
      final createdInterface = interfacesAfterStart
          .difference(interfacesBeforeStart)
          .firstOrNull;
      if (createdInterface != null) {
        _tunInterface = createdInterface;
      } else if (_tunInterface != null &&
          !interfacesAfterStart.contains(_tunInterface)) {
        _tunInterface = null;
      }
      if (_tunInterface == null) {
        Log.w('unable to identify Clash TUN interface after start');
      }
    } else if (!vpnEnabled) {
      _tunInterface = null;
    }

    return err;
  }

  static Future<Set<String>> _listTunInterfaces() async {
    final result = await Process.run('/sbin/ifconfig', ['-l']);
    if (result.exitCode != 0) {
      throw ProcessException(
        '/sbin/ifconfig',
        const ['-l'],
        '${result.stderr}',
        result.exitCode,
      );
    }

    return (result.stdout as String)
        .trim()
        .split(RegExp(r'\s+'))
        .where((name) => name.startsWith('utun'))
        .toSet();
  }

  static Future<String?> _stopSingle() async {
    String? err;
    final wasStarted = _started;

    using((arena) {
      try {
        final res = stopTun();
        if (res != nullptr) {
          final error = res.cast<Utf8>().toDartString();
          if (error.isNotEmpty) {
            err = error;
            Log.e('stop Error: $error');
          }
          freeString(res);
          _started = err != null ? wasStarted : false;
        } else {
          _started = false;
        }
      } catch (e) {
        Log.e('stop error: $e');
        _started = wasStarted;
      }
    });

    if (!_started) _clashKey = null;
    if (!_started) _vpnEnabled = false;

    return err;
  }
}
