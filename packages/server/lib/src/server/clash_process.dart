import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:clash_core/clash_core.dart';
import 'package:server/src/clash_wake_monitor_bindings_generated.dart';
import 'package:dio/dio.dart';
import 'package:ffi/ffi.dart';
import 'package:nop/nop.dart';
import 'package:path/path.dart' as p;
import 'package:js_interpreter/js_interpreter.dart';
import 'package:server/app_support.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_writer/yaml_writer.dart';

import 'config_overrides.dart';
import 'desktop_tun_helper.dart';
import 'models/models.dart';

final _clashQueue = TaskQueue();
final _stateQueue = TaskQueue();

bool get _isDesktop =>
    Platform.isMacOS || Platform.isLinux || Platform.isWindows;

abstract final class ClashProcess {
  static const _wakeNetworkSettleDelay = Duration(seconds: 5);
  static final _stateFilePath = _resolveStateFilePath();

  static final _stateFile = File(_stateFilePath);
  static ReceivePort? _wakeEvents;
  static StreamSubscription<dynamic>? _wakeSubscription;
  static Isolate? _wakeMonitor;
  static bool _recoveringTunAfterWake = false;
  static String? _tunInterface;

  static ClashProfile? _profile;
  static ClashProfile? _apiProfile;
  static Timer? _profileTimer;
  // Desired state: hydrated from disk and changed only by API commits.
  static var _desiredVpnEnabled = false;
  // Observed runtime state: changed by native start/stop operations.
  static var _runtimeVpnEnabled = false;

  static String _resolveStateFilePath() {
    if (Platform.isMacOS) {
      return p.join(clashyApplicationSupportDirectory, 'clash-state.json');
    }
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return p.join(appData, 'Clashy', 'clash-state.json');
      }
    }
    // Linux 及其他 POSIX 平台：遵循 XDG_CONFIG_HOME，缺省 ~/.config。
    final configHome = Platform.environment['XDG_CONFIG_HOME'];
    final base = configHome != null && configHome.isNotEmpty
        ? configHome
        : p.join(Platform.environment['HOME'] ?? '.', '.config');
    return p.join(base, 'clashy', 'clash-state.json');
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
      final configDir = profile?.configDir;

      final vpnEnabled = state['vpnEnabled'] is bool
          ? state['vpnEnabled'] as bool
          : true;
      if (configDir == null || configDir.isEmpty) {
        Log.e('saved Clash state has no configuration directory');
        return;
      }

      _apiProfile = profile;
      _desiredVpnEnabled = vpnEnabled;
      Log.w('restoring Clash from saved state ${_stateFile.path}');
      final error = vpnEnabled
          ? await run(configDir)
          : await runCoreOnly(configDir);
      if (error != null) {
        Log.e('restore Clash from saved state failed: $error');
        return;
      }
      if (profile != null) _replaceRuntimeProfile(profile);
    } catch (e) {
      Log.e('restore Clash from saved state failed: $e');
    }
  }

  /// Commits desired state submitted through the control API.
  /// Runtime recovery and background work must never call this method.
  static Future<void> commitApiState({
    ClashProfile? profile,
    required bool vpnEnabled,
  }) async {
    if (Platform.isMacOS) {
      await _stateQueue.run(() async {
        final temporaryFile = File('$_stateFilePath.tmp');
        await temporaryFile.create(recursive: true);
        await temporaryFile.writeAsString(
          jsonEncode({'profile': profile?.toJson(), 'vpnEnabled': vpnEnabled}),
          flush: true,
        );
        await temporaryFile.rename(_stateFilePath);
      });
    }
    _apiProfile = profile;
    _desiredVpnEnabled = vpnEnabled;
  }

  /// Clears desired state after an explicit stop request through the API.
  static Future<void> clearApiState() async {
    if (Platform.isMacOS) {
      await _stateQueue.run(() async {
        if (await _stateFile.exists()) {
          await _stateFile.delete();
        }
      });
    }
    _apiProfile = null;
    _desiredVpnEnabled = false;
  }

  static Future<void> initialize() async {
    await restorePersistedClash();
    try {
      await startMacOSWakeMonitor();
    } catch (e) {
      Log.e('start macOS wake monitor failed: $e');
    }
  }

  static Future<void> startMacOSWakeMonitor() async {
    if (!Platform.isMacOS ||
        _wakeMonitor != null ||
        _wakeEvents != null ||
        _wakeSubscription != null) {
      return;
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
    _wakeMonitor = await Isolate.spawn(
      _watchMacOSWake,
      events.sendPort,
      debugName: 'clashy-macos-wake-monitor',
    );
  }

  @pragma('vm:entry-point')
  static void _watchMacOSWake(SendPort sendPort) {
    try {
      if (clashy_wake_monitor_start() != 0) {
        throw StateError('IOKit power notification registration failed');
      }

      sendPort.send('ready');
      while (true) {
        if (clashy_wake_monitor_wait() != 0) {
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
        !_desiredVpnEnabled ||
        !_runtimeVpnEnabled ||
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

        final vpnEnabled = _desiredVpnEnabled;
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

  /// Whether the native core currently has TUN enabled.
  static bool get vpnEnabled => _runtimeVpnEnabled;

  /// VPN mode last requested through the control API.
  static bool get desiredVpnEnabled => _desiredVpnEnabled;

  static ClashProfile? get profile => _profile;

  static ClashProfile? get apiProfile => _apiProfile;

  static String? get configDir => _clashKey;

  static Future<String?> run(String configDir) async {
    return _clashQueue.run(() => _runSingle(configDir, vpnEnabled: true));
  }

  static Future<String?> runCoreOnly(String configDir) async {
    return _clashQueue.run(() => _runSingle(configDir, vpnEnabled: false));
  }

  static Future<void> setProfile(ClashProfile profile) async {
    _replaceRuntimeProfile(profile);
  }

  static Future<void> updateProfile(ClashProfile profile) async {
    final current = _profile;
    final currentConfigDir = current?.configDir ?? _clashKey;
    _replaceRuntimeProfile(
      profile.configDir.isEmpty && currentConfigDir != null
          ? profile.copyWith(configDir: currentConfigDir)
          : profile,
    );
  }

  static Future<String?> stopVpn() async {
    final configDir = _clashKey;
    if (!_started || configDir == null) {
      return null;
    }

    return runCoreOnly(configDir);
  }

  static Future<String?> reloadConfig() async {
    return _clashQueue.run(() async {
      if (!_started || _clashKey == null) {
        return 'Clash core is not running';
      }

      final configDir = _clashKey!;
      final vpnEnabled = _desiredVpnEnabled;
      final stopError = await _stopSingle();
      if (stopError != null) return stopError;
      return _runSingle(configDir, vpnEnabled: vpnEnabled);
    });
  }

  /// Stops the runtime without changing persisted desired state.
  /// The HTTP stop endpoint separately clears it after a successful stop.
  static Future<String?> stop() async {
    final err = await _clashQueue.run(_stopSingle);
    if (err case var err? when err.isNotEmpty) return err;
    _profileTimer?.cancel();
    _profileTimer = null;
    _profile = null;
    return null;
  }

  static void _replaceRuntimeProfile(ClashProfile profile) {
    _profile = profile;
    _scheduleProfileUpdate();
    Log.w(profile.toJson().logPretter);
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
    if (profile == null) {
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
        _replaceRuntimeProfile(profile.copyWith(updateTime: DateTime.now()));
        Log.i('profile updated: ${profile.name ?? profile.id ?? profile.url}');
        return;
      }
    } catch (e) {
      Log.e('profile update failed: ${profile.url} $e');
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
    final script = profile.script;
    final configured = script == null || script.trim().isEmpty
        ? merged
        : _runProfileScript(merged, script);

    final backupPath = '${configFile.path}.bak';
    final backup = File(backupPath);
    await configFile.copy(backupPath);
    await _writeConfig(configFile, configured);

    var vpnEnabled = false;
    final error = await _clashQueue.run(() async {
      if (!_started || !identical(_profile, profile)) return null;
      vpnEnabled = _desiredVpnEnabled;
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

  static String _runProfileScript(String yaml, String script) {
    final js = JSInterpreter();
    try {
      final data = jsonDecode(jsonEncode(loadYaml(yaml)));
      // final scriptErrors = <String?>[];
      js.eval(script);
      // , filename: 'profile-script.js', errMsg: scriptErrors);
      // if (scriptErrors.isNotEmpty) {
      //   throw FormatException(
      //     scriptErrors.first ?? 'unable to evaluate profile script',
      //   );
      // }

      js.setGlobal('profileConfig', data);
      final resultErrors = <String?>[];
      final result = js.evalToDart(
        'main(profileConfig);',
        // filename: 'profile-script-main.js',
        // errMsg: resultErrors,
      );
      if (resultErrors.isNotEmpty) {
        throw FormatException(
          resultErrors.first ?? 'unable to execute profile script',
        );
      }
      if (result == null) {
        throw const FormatException('profile script returned no config');
      }

      final config = jsonDecode(result);
      if (config is! Map) {
        throw const FormatException('profile script must return a config map');
      }
      return YamlWriter().write(config.cast<String, dynamic>());
    } catch (e) {
      Log.e('profile script failed: $e');
      return yaml;
    } finally {
      // js.close();
    }
  }

  static Future<String> _downloadConfig(String url) async {
    final client = Dio(.new(connectTimeout: const Duration(seconds: 15)));
    try {
      final responseFile = await client.get<String>(
        url,
        options: .new(
          responseType: ResponseType.plain,
          headers: {'User-Agent': 'clash/mihomo'},
        ),
      );
      final fileData = responseFile.data;
      Log.w('data: $fileData');
      return fileData ?? '';
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
      if (_started && _runtimeVpnEnabled == vpnEnabled) {
        return null;
      }
    }

    if (_isDesktop && vpnEnabled) {
      try {
        await DesktopTunHelper.ensureRegistered();
      } catch (error) {
        Log.e('register TUN helper failed: $error');
        return 'register TUN helper failed: $error';
      }
    }

    final interfacesBeforeStart = Platform.isMacOS
        ? await _listTunInterfaces()
        : const <String>{};

    String? err;
    _started = false;
    _runtimeVpnEnabled = false;
    using((arena) {
      try {
        final nativeConfigDir = configDir
            .toNativeUtf8(allocator: arena)
            .cast<Char>();
        final res = _isDesktop
            ? startTun(nativeConfigDir, vpnEnabled ? -1 : 0)
            : vpnEnabled
            ? start(nativeConfigDir)
            : startTun(nativeConfigDir, 0);
        if (res != nullptr) {
          final error = res.cast<Utf8>().toDartString();
          if (error.isNotEmpty) {
            err = error;
            Log.e('start Error: $error');
          }
          freeString(res);
        } else {
          _started = true;
        }
      } catch (e) {
        Log.e('start error: $e');
        err = e.toString();
      }
    });

    _clashKey = configDir;
    _runtimeVpnEnabled = err == null && _started && vpnEnabled;
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

    if (!_started) {
      _clashKey = null;
      _runtimeVpnEnabled = false;
    }

    return err;
  }
}
