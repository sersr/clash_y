import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:server/server.dart' show ClashProfile;

abstract final class IOSVpnService {
  static const _channel = MethodChannel('clash_service/ios');
  static const _configDirectoryName = 'clash_config';

  static Future<String> get controlSocketPath async {
    final appGroup = await _appGroupDirectory();
    return p.join(appGroup, _configDirectoryName, 'socket_clash.sock');
  }

  static Future<String> get sharedConfigDirectory async {
    final appGroup = await _appGroupDirectory();
    return p.join(appGroup, _configDirectoryName);
  }

  static Future<String> _appGroupDirectory() async {
    final path = await _channel.invokeMethod<String>('appGroupDirectory');
    if (path == null || path.isEmpty) {
      throw StateError('The iOS VPN App Group container is unavailable.');
    }
    return path;
  }

  static Future<bool> isConfigured() async {
    return await _channel.invokeMethod<bool>('isConfigured') ?? false;
  }

  static Future<bool> start(ClashProfile profile) async {
    final configDirectory = await sharedConfigDirectory;
    await _copyConfigDirectory(profile.configDir, configDirectory);
    return await _channel.invokeMethod<bool>('start', {
          'configDir': configDirectory,
        }) ??
        false;
  }

  static Future<bool> updateProfile(ClashProfile profile) async {
    final configDirectory = await sharedConfigDirectory;
    await _copyConfigDirectory(profile.configDir, configDirectory);
    return await _channel.invokeMethod<bool>('updateProfile', {
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

    final destination = Directory(destinationPath);
    await destination.create(recursive: true);
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      final relativePath = p.relative(entity.path, from: sourcePath);
      final targetPath = p.join(destinationPath, relativePath);
      switch (entity) {
        case File file:
          final target = File(targetPath);
          await target.parent.create(recursive: true);
          await file.copy(target.path);
        case Directory _:
          await Directory(targetPath).create(recursive: true);
        case Link link:
          throw FileSystemException(
            'Profile configuration contains a symbolic link',
            link.path,
          );
      }
    }
  }
}
