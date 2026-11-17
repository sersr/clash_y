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

  static String? _iosControlSocketPath;

  static File getCacheFile(String url) {
    return fs.currentDirectory.childFile(join(appCachePath, basename(url)));
  }

  static String get unixSocketPath {
    return switch (defaultTargetPlatform) {
      .windows => r"\\.\pipe\clashy.pipe",
      .iOS => _iosControlSocketPath ?? '',
      _ => join(G.appCachePath, 'clash_config', 'socket_clash.sock'),
    };
  }

  static Future<void> init() async {
    await [
      if (defaultTargetPlatform == .iOS)
        Future(
          () async =>
              _iosControlSocketPath = await ClashService.iosControlSocketPath,
        ),
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

    return Hives.init(join(appSubPath, 'hives'));
  }
}
