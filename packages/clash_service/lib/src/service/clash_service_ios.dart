import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:server/server.dart' show ClashProfile;

abstract final class IOSVpnService {
  static const _channel = MethodChannel('clash_service/ios');
  static const _configDirectoryName = 'clash_config';

  /// Records which files the app copied last time so a later sync can drop
  /// files the previous profile owned without touching mihomo's own runtime
  /// data (geoip.dat, cache.db, ...) that lives in the same directory.
  static const _manifestName = '.profile_files';

  /// The control socket lives in the App Group root, not inside the profile
  /// directory: `sockaddr_un.sun_path` is capped at 104 bytes on Darwin and
  /// the container prefix alone is ~83 characters, so every byte counts. A
  /// longer path makes mihomo's unix listener fail with ENOENT/EINVAL while
  /// the tunnel still reports connected, leaving the UI without an API.
  static const _controlSocketName = 'c.sock';

  static Future<String> get controlSocketPath async {
    final appGroup = await _appGroupDirectory();
    return p.join(appGroup, _controlSocketName);
  }

  static Future<String> get sharedConfigDirectory async {
    final appGroup = await _appGroupDirectory();
    return p.join(appGroup, _configDirectoryName);
  }

  /// The App Group container never moves while the process lives, and the
  /// channel round trip hops to the main thread, so ask once and keep it.
  static Future<String> _appGroupDirectory() =>
      _appGroup ??= _queryAppGroupDirectory();

  static Future<String>? _appGroup;

  static Future<String> _queryAppGroupDirectory() async {
    final path = await _channel.invokeMethod<String>('appGroupDirectory');
    if (path == null || path.isEmpty) {
      throw StateError('The iOS VPN App Group container is unavailable.');
    }
    return path;
  }

  static Future<bool> isConfigured() async {
    return await _channel.invokeMethod<bool>('isConfigured') ?? false;
  }

  static Future<bool> isActive() async {
    return await _channel.invokeMethod<bool>('isActive') ?? false;
  }

  static Future<bool> start(ClashProfile profile) async {
    final configDirectory = await sharedConfigDirectory;
    await _copyConfigDirectory(profile.configDir, configDirectory);
    return await _channel.invokeMethod<bool>('start', {
          'configDir': configDirectory,
        }) ??
        false;
  }

  static Future<bool> close() async {
    return await _channel.invokeMethod<bool>('stop') ?? false;
  }

  static Future<bool> uninstall() async {
    return await _channel.invokeMethod<bool>('uninstall') ?? false;
  }

  static Future<void> _copyConfigDirectory(
    String sourcePath,
    String destinationPath,
  ) async {
    final source = Directory(sourcePath);
    if (!await source.exists()) {
      throw FileSystemException(
        'Profile configuration directory not found',
        sourcePath,
      );
    }
    if (!await File(p.join(sourcePath, 'config.yaml')).exists()) {
      throw FileSystemException('Profile config.yaml not found', sourcePath);
    }

    // Walk the source first: a symbolic link or an unreadable entry must abort
    // the sync before anything in the shared directory is modified, otherwise
    // the tunnel could be left with a half copied profile.
    final files = <String, File>{};
    final directories = <String>[];
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      final relativePath = p.relative(entity.path, from: sourcePath);
      switch (entity) {
        case File file:
          files[relativePath] = file;
        case Directory _:
          directories.add(relativePath);
        case Link link:
          throw FileSystemException(
            'Profile configuration contains a symbolic link',
            link.path,
          );
      }
    }

    final destination = Directory(destinationPath);
    await destination.create(recursive: true);

    for (final relativePath in directories) {
      await Directory(p.join(destinationPath, relativePath))
          .create(recursive: true);
    }
    for (final entry in files.entries) {
      final target = File(p.join(destinationPath, entry.key));
      await target.parent.create(recursive: true);
      // config.yaml becomes the core's file once the tunnel has written it:
      // otherwise a later start would copy the app's older config back over a
      // subscription the core refreshed in the background.
      if (entry.key == 'config.yaml' && await target.exists()) continue;
      await entry.value.copy(target.path);
    }

    await _removeStaleFiles(destinationPath, files.keys.toSet());
  }

  /// Deletes files copied by a previous sync that the current profile no longer
  /// ships. Only files listed in the manifest are considered, so mihomo's own
  /// databases and caches in the same directory survive a profile switch.
  static Future<void> _removeStaleFiles(
    String destinationPath,
    Set<String> currentFiles,
  ) async {
    final manifest = File(p.join(destinationPath, _manifestName));
    if (await manifest.exists()) {
      final previous = await manifest.readAsLines();
      for (final relativePath in previous) {
        if (relativePath.isEmpty || currentFiles.contains(relativePath)) {
          continue;
        }
        final file = File(p.join(destinationPath, relativePath));
        if (await file.exists()) {
          try {
            await file.delete();
          } on FileSystemException {
            // A file mihomo holds open is not worth failing the sync over.
          }
        }
      }
    }

    final sorted = currentFiles.toList()..sort();
    await manifest.writeAsString(
      sorted.isEmpty ? '' : '${sorted.join('\n')}\n',
      flush: true,
    );
  }
}
