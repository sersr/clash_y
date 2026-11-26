import 'package:clash_service/clash_service.dart' show ClashService, fs;
import 'package:common/src/hive.dart';
import 'package:file/file.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

abstract final class G {
  static String? _appPath;
  static String get appPath => _appPath!;
  static String? _appCachePath;
  static String get appCachePath => _appCachePath!;
  static String? _appSubPath;
  static String get appSubPath => _appSubPath!;
  static String get appConfigPath => join(appSubPath, 'clash_config');

  static String? _unixSocketPath;

  /// Controller socket of the mihomo core; written into the profile as
  /// `external-controller-unix` and used by `ClashApi`.
  static String get unixSocketPath => _unixSocketPath!;

  static File getCacheFile(String url) {
    return fs.currentDirectory.childFile(join(appCachePath, basename(url)));
  }

  static Future<void> init() async {
    await [
      getApplicationDocumentsDirectory().then((docDir) {
        _appPath = join(docDir.path, 'clashy');
      }),
      getApplicationSupportDirectory().then((dir) {
        _appSubPath = join(dir.path, 'clashy');
      }),
      getApplicationCacheDirectory().then((cache) {
        _appCachePath = join(cache.path, 'clashy');
      }),
    ].wait;

    // iOS keeps the core socket in the App Group, so the tunnel process can
    // reach it; that lookup needs the platform channel and runs after the
    // plain path lookups above.
    _unixSocketPath = switch (defaultTargetPlatform) {
      .windows => r"\\.\pipe\clashy.pipe",
      .iOS => await ClashService.iosControlSocketPath,
      _ => join(appCachePath, 'clash_config', 'socket_clash.sock'),
    };

    return Hives.init(join(appSubPath, 'hives'));
  }

  @visibleForTesting
  static Future<void> initTest() async {
    final docDir = './.testData/doc';
    final dir = './.testData/dir';
    final cache = './.testData/cache';
    _appPath = join(docDir, 'clashy');

    _appSubPath = join(dir, 'clashy');
    _appCachePath = join(cache, 'clashy');
    _unixSocketPath = join(_appCachePath!, 'clash_config', 'socket_clash.sock');

    return Hives.init(join(appSubPath, 'hives'));
  }
}
