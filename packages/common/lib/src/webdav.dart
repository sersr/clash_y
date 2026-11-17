import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:common/src/fs.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:simple_secure_storage/simple_secure_storage.dart';
import 'package:webdav_client_plus/webdav_client_plus.dart';

import 'global.dart';
import 'hive.dart';

const _passwordKey = 'webdav.backup.password';
const _remoteArchiveName = 'clashy-backup.zip';
const _manifestName = 'hive/.clashy-backup.json';
const _hiveSnapshotName = 'hive/.clashy-hives.json';

class WebDavBackupSettings {
  const WebDavBackupSettings({
    this.url = '',
    this.username = '',
    this.remotePath = '/clashy-backup',
    this.autoSync = false,
  });

  final String url;
  final String username;
  final String remotePath;
  final bool autoSync;

  factory WebDavBackupSettings.fromJson(Map<String, dynamic> json) {
    return WebDavBackupSettings(
      url: json['url'] as String? ?? '',
      username: json['username'] as String? ?? '',
      remotePath: json['remotePath'] as String? ?? '/clashy-backup',
      autoSync: json['autoSync'] as bool? ?? false,
    );
  }

  Map<String, Object> toJson() => {
    'url': url,
    'username': username,
    'remotePath': remotePath,
    'autoSync': autoSync,
  };
}

class WebDavSyncResult {
  const WebDavSyncResult({required this.message, this.restored = false});

  final String message;
  final bool restored;
}

class WebDavBackupService {
  static Future<void>? _secureStorageInitialization;

  WebDavBackupSettings loadSettings() => WebDavHive.settings.value;

  Future<void> saveSettings(
    WebDavBackupSettings settings, {
    required String password,
  }) async {
    final remotePath = _normalizeRemotePath(settings.remotePath);
    if (settings.url.trim().isNotEmpty) {
      _validatedUri(settings.url, settings.username, password);
    }

    if (password.isNotEmpty) {
      await _ensureSecureStorage();
      await SimpleSecureStorage.write(_passwordKey, password);
    } else if (settings.username.trim().isEmpty) {
      await _ensureSecureStorage();
      await SimpleSecureStorage.delete(_passwordKey);
    }

    final normalized = WebDavBackupSettings(
      url: settings.url.trim().replaceFirst(RegExp(r'/+$'), ''),
      username: settings.username.trim(),
      remotePath: remotePath,
      autoSync: settings.autoSync,
    );
    WebDavHive.settings.value = normalized;
  }

  Future<DateTime?> lastSyncAt() async {
    final value = WebDavHive.lastSyncAt.value;
    return DateTime.tryParse(value);
  }

  Future<void> testConnection() async {
    final settings = loadSettings();
    final client = await _clientFor(settings);
    await client.ping();
    await client.mkdirAll(settings.remotePath);
    await client.readDir(settings.remotePath);
  }

  Future<File> exportArchive(String destinationPath) async {
    final destination = File(destinationPath);
    await destination.parent.create(recursive: true);
    await _writeSnapshot(destination);
    return destination;
  }

  Future<void> restoreArchive(String archivePath) async {
    final archiveFile = File(archivePath);
    if (!await archiveFile.exists()) {
      throw StateError('The selected ZIP backup does not exist.');
    }

    final decoded = await _decodeSnapshot(archiveFile);
    try {
      await _restoreSnapshot(decoded.archive);
    } finally {
      await decoded.input.close();
    }
  }

  Future<WebDavSyncResult> synchronize() async {
    final settings = loadSettings();
    final client = await _clientFor(settings);
    await client.mkdirAll(settings.remotePath);

    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'clashy-webdav-',
    );
    final localArchive = File(p.join(temporaryDirectory.path, 'local.zip'));
    final remoteArchive = File(p.join(temporaryDirectory.path, 'remote.zip'));

    try {
      final localSnapshot = await _writeSnapshot(localArchive);
      final remotePath = _remoteArchivePath(settings.remotePath);
      if (!await client.exists(remotePath)) {
        await client.writeFile(localArchive.path, remotePath);
        await _saveLastSyncAt();
        return const WebDavSyncResult(message: 'Uploaded local backup.');
      }

      await client.readFile(remotePath, remoteArchive.path);
      final decodedRemote = await _decodeSnapshot(remoteArchive);
      try {
        if (await lastSyncAt() == null) {
          await _restoreSnapshot(decodedRemote.archive);
          await _saveLastSyncAt();
          return const WebDavSyncResult(
            message: 'Restored remote backup on first sync.',
            restored: true,
          );
        }

        if (localSnapshot.modifiedAt.isAfter(decodedRemote.modifiedAt) ||
            (localSnapshot.modifiedAt.isAtSameMomentAs(
                  decodedRemote.modifiedAt,
                ) &&
                localSnapshot.sha256 != decodedRemote.sha256)) {
          await client.writeFile(localArchive.path, remotePath);
          await _saveLastSyncAt();
          return const WebDavSyncResult(message: 'Uploaded local backup.');
        }

        if (decodedRemote.modifiedAt.isAfter(localSnapshot.modifiedAt)) {
          await _restoreSnapshot(decodedRemote.archive);
          await _saveLastSyncAt();
          return const WebDavSyncResult(
            message: 'Restored newer remote backup.',
            restored: true,
          );
        }

        await _saveLastSyncAt();
        return const WebDavSyncResult(message: 'Backups are already in sync.');
      } finally {
        await decodedRemote.input.close();
      }
    } finally {
      await temporaryDirectory.delete(recursive: true);
    }
  }

  Future<WebdavClient> _clientFor(WebDavBackupSettings settings) async {
    final uri = _validatedUri(settings.url, settings.username, null);
    final password = await _readPassword();
    final username = settings.username.trim();
    if (username.isNotEmpty && (password == null || password.isEmpty)) {
      throw StateError('Enter the WebDAV password before connecting.');
    }
    if (username.isEmpty && password != null && password.isNotEmpty) {
      throw StateError('A WebDAV username is required when using a password.');
    }

    return username.isEmpty
        ? WebdavClient.noAuth(url: uri.toString())
        : WebdavClient.basicAuth(
            url: uri.toString(),
            user: username,
            pwd: password!,
          );
  }

  Uri _validatedUri(String value, String username, String? password) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException(
        'Enter a valid WebDAV URL without embedded credentials or query parameters.',
      );
    }

    // if ((username.trim().isNotEmpty || (password?.isNotEmpty ?? false)) &&
    //     uri.scheme.toLowerCase() != 'https') {
    //   throw const FormatException(
    //     'WebDAV authentication requires an HTTPS URL.',
    //   );
    // }

    return uri.replace(path: uri.path.replaceFirst(RegExp(r'/+$'), ''));
  }

  String _normalizeRemotePath(String value) {
    final path = value.trim();
    if (path.contains(r'\') || path.contains('?') || path.contains('#')) {
      throw const FormatException('Enter a valid WebDAV folder path.');
    }
    final segments = path.split('/').where((part) => part.isNotEmpty).toList();
    if (segments.any((part) => part == '.' || part == '..')) {
      throw const FormatException(
        'The WebDAV folder path cannot contain "." or "..".',
      );
    }
    return '/${segments.join('/')}';
  }

  Future<String?> _readPassword() async {
    await _ensureSecureStorage();
    return SimpleSecureStorage.read(_passwordKey);
  }

  Future<void> _ensureSecureStorage() =>
      _secureStorageInitialization ??= SimpleSecureStorage.initialize();

  String _remoteArchivePath(String remotePath) {
    final base = remotePath == '/' ? '' : remotePath;
    return '$base/$_remoteArchiveName';
  }

  Future<_LocalSnapshot> _writeSnapshot(File outputFile) async {
    await outputFile.parent.create(recursive: true);
    await Future.wait(
      Hives.values
          .where((hive) => hive != Hives.webdav)
          .map((hive) => hive.box.flush()),
    );

    final hiveData = <String, Object?>{};
    for (final hive in Hives.values.where((hive) => hive != Hives.webdav)) {
      final box = hive.box;
      final values = SplayTreeMap<String, dynamic>();
      for (final key in box.keys) {
        values[key.toString()] = box.get(key);
      }
      hiveData[hive.name] = values;
    }

    final archive = Archive();
    var latestModified = DateTime.fromMillisecondsSinceEpoch(0);
    final configFile = configYaml;
    if (await configFile.exists()) {
      final stat = await configFile.stat();
      latestModified = stat.modified;
      archive.addFile(
        ArchiveFile.stream(
          'clash-settings/config.yaml',
          InputFileStream(configFile.path),
        )..lastModTime = stat.modified.millisecondsSinceEpoch ~/ 1000,
      );
    }

    final hiveDirectory = Directory(p.join(G.appSubPath, 'hives'));
    if (await hiveDirectory.exists()) {
      await for (final entity in hiveDirectory.list(followLinks: false)) {
        if (await FileSystemEntity.type(entity.path, followLinks: false) !=
            FileSystemEntityType.file) {
          continue;
        }
        final modified = (await File(entity.path).stat()).modified;
        if (modified.isAfter(latestModified)) latestModified = modified;
      }
    }

    final hiveSnapshot = ArchiveFile.string(
      _hiveSnapshotName,
      jsonEncode(hiveData),
    )..lastModTime = latestModified.millisecondsSinceEpoch ~/ 1000;
    archive.addFile(hiveSnapshot);
    archive.addFile(
      ArchiveFile.string(
        _manifestName,
        jsonEncode({
          'formatVersion': 1,
          'modifiedAt': latestModified.millisecondsSinceEpoch,
        }),
      )..lastModTime = latestModified.millisecondsSinceEpoch ~/ 1000,
    );

    final output = OutputFileStream(outputFile.path);
    try {
      ZipEncoder(streamed: true).encodeStream(archive, output);
    } finally {
      await output.close();
      await archive.clear();
    }

    final digest = await sha256.bind(outputFile.openRead()).first;
    return _LocalSnapshot(latestModified, digest.toString());
  }

  Future<_DecodedSnapshot> _decodeSnapshot(File file) async {
    final input = InputFileStream(file.path);
    try {
      final archive = ZipDecoder().decodeStream(
        input,
        verify: true,
        throwOnError: true,
      );
      final names = <String>{};
      final fileNames = <String>{};
      for (final entry in archive.files) {
        if (entry.isSymbolicLink || entry.isHardLink) {
          throw const FormatException('Backup contains a link entry.');
        }
        final path = _validateArchivePath(entry.name);
        if (!names.add(path)) {
          throw const FormatException('Backup contains duplicate entries.');
        }
        if (!entry.isDirectory) fileNames.add(path);
      }
      for (final path in names) {
        final segments = path.split('/');
        for (var index = 1; index < segments.length; index++) {
          if (fileNames.contains(segments.take(index).join('/'))) {
            throw const FormatException(
              'Backup contains a file used as a directory.',
            );
          }
        }
      }

      final manifest = archive.find(_manifestName);
      if (manifest == null || manifest.isDirectory || manifest.size > 65536) {
        throw const FormatException('Backup manifest is missing.');
      }
      final manifestData = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(manifest.content)) as Map,
      );
      if (manifestData['formatVersion'] != 1 ||
          manifestData['modifiedAt'] is! int) {
        throw const FormatException('Backup format is not supported.');
      }

      final hiveSnapshot = archive.find(_hiveSnapshotName);
      if (hiveSnapshot == null ||
          hiveSnapshot.isDirectory ||
          hiveSnapshot.size > 16 * 1024 * 1024) {
        throw const FormatException('Hive snapshot is missing.');
      }

      final digest = (await sha256.bind(file.openRead()).first).toString();
      final modifiedAt = DateTime.fromMillisecondsSinceEpoch(
        manifestData['modifiedAt'] as int,
      );
      return _DecodedSnapshot(input, archive, modifiedAt, digest);
    } catch (_) {
      input.closeSync();
      rethrow;
    }
  }

  String _validateArchivePath(String value) {
    if (value.isEmpty || value.contains(r'\') || value.startsWith('/')) {
      throw const FormatException('Backup contains an invalid path.');
    }
    final clean = value.endsWith('/')
        ? value.substring(0, value.length - 1)
        : value;
    final segments = clean.split('/');
    if (segments.length < 2 ||
        !const {'app', 'hive', 'clash-settings'}.contains(segments.first) ||
        segments.any(
          (segment) =>
              segment.isEmpty ||
              segment == '.' ||
              segment == '..' ||
              segment.contains(':'),
        ) ||
        (segments.first == 'app' && segments[1] == 'caches') ||
        (segments.first == 'clash-settings' &&
            (segments.length != 2 || segments[1] != 'config.yaml'))) {
      throw const FormatException('Backup contains an invalid path.');
    }
    return clean;
  }

  Future<void> _restoreSnapshot(Archive archive) async {
    final hiveSnapshot = archive.find(_hiveSnapshotName)!;
    final hiveData = Map<String, dynamic>.from(
      jsonDecode(utf8.decode(hiveSnapshot.content)) as Map,
    );
    final supportedBoxes = Hives.values
        .where((hive) => hive != Hives.webdav)
        .map((hive) => hive.name)
        .toSet();
    if (hiveData.keys.any((name) => !supportedBoxes.contains(name))) {
      throw const FormatException('Backup contains an unknown Hive box.');
    }
    final restoredBoxes = <String, Map<String, dynamic>>{};
    for (final hive in Hives.values.where((hive) => hive != Hives.webdav)) {
      final values = hiveData[hive.name];
      if (values != null && values is! Map) {
        throw const FormatException('Backup contains invalid Hive data.');
      }
      final boxData = Map<String, dynamic>.from(values as Map? ?? const {});
      if (boxData.values.any((value) => value is! String)) {
        throw const FormatException('Backup contains invalid Hive values.');
      }
      restoredBoxes[hive.name] = boxData;
    }

    for (final entry in archive.files) {
      if (entry.name == _manifestName || entry.name == _hiveSnapshotName) {
        continue;
      }
      final segments = _validateArchivePath(entry.name).split('/');
      if (!_isConfigYaml(segments)) continue;
      final root = _archiveRoot(segments);
      await _ensureNoSymlinkAncestors(root, segments.skip(1));
    }

    for (final entry in archive.files) {
      if (entry.name == _manifestName || entry.name == _hiveSnapshotName) {
        continue;
      }
      final clean = _validateArchivePath(entry.name);
      final segments = clean.split('/');
      if (!_isConfigYaml(segments)) continue;
      final root = _archiveRoot(segments);
      final target = p.normalize(p.joinAll([root, ...segments.skip(1)]));
      if (!p.isWithin(p.normalize(p.absolute(root)), p.absolute(target))) {
        throw const FormatException('Backup path escapes its destination.');
      }
      if (entry.isDirectory) {
        await Directory(target).create(recursive: true);
      } else {
        final outputFile = File(target);
        await outputFile.parent.create(recursive: true);
        final output = OutputFileStream(target);
        try {
          entry.writeContent(output);
        } finally {
          await output.close();
        }
        await outputFile.setLastModified(entry.lastModDateTime);
      }
    }

    for (final hive in Hives.values.where((hive) => hive != Hives.webdav)) {
      final box = hive.box;
      await box.clear();
      await box.putAll(restoredBoxes[hive.name]!);
    }
    for (final item in Hives.items) {
      item.target.refresh(item.key, item.transform);
    }
  }

  bool _isConfigYaml(List<String> segments) =>
      segments.length == 2 &&
      segments[0] == 'clash-settings' &&
      segments[1] == 'config.yaml';

  String _archiveRoot(List<String> segments) =>
      segments.first == 'clash-settings'
      ? p.join(G.appSubPath, 'clash_config')
      : segments.first == 'app'
      ? G.appPath
      : G.appSubPath;

  Future<void> _ensureNoSymlinkAncestors(
    String root,
    Iterable<String> segments,
  ) async {
    var current = p.normalize(p.absolute(root));
    if (await FileSystemEntity.type(current, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const FormatException(
        'Backup destination contains a symbolic link.',
      );
    }
    for (final segment in segments) {
      current = p.join(current, segment);
      if (await FileSystemEntity.type(current, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const FormatException(
          'Backup destination contains a symbolic link.',
        );
      }
    }
  }

  Future<void> _saveLastSyncAt() async {
    WebDavHive.lastSyncAt.value = DateTime.now().toUtc().toIso8601String();
  }
}

class _LocalSnapshot {
  const _LocalSnapshot(this.modifiedAt, this.sha256);

  final DateTime modifiedAt;
  final String sha256;
}

class _DecodedSnapshot {
  const _DecodedSnapshot(
    this.input,
    this.archive,
    this.modifiedAt,
    this.sha256,
  );

  final InputFileStream input;
  final Archive archive;
  final DateTime modifiedAt;
  final String sha256;
}
