import 'package:common/src/hive.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

abstract final class G {
  static String? _appPath;
  static String get appPath => _appPath!;
  static String? _appCachePath;
  static String get appCachePath => _appCachePath!;
  static String? _appSubPath;
  static String get appSubPath => _appSubPath!;

  static Future<void> init() async {
    await [
      getApplicationDocumentsDirectory().then((docDir) {
        _appPath = join(docDir.path, 'clash_y');
      }),
      getApplicationSupportDirectory().then((dir) {
        _appSubPath = join(dir.path, 'clash_y');
      }),
      getApplicationCacheDirectory().then((cache) {
        _appCachePath = join(cache.path, 'clash_y');
      }),
    ].wait;

    return Hives.init(join(appSubPath, 'hives'));
  }
}

abstract final class HiveConfig {
  static String get unixSockPath {
    final value = Hives.config.get('unixSockPath');
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }
    return join(G.appCachePath, 'clash_config', 'socket_clash.sock');
  }

  static set unixSocketPath(String n) {
    Hives.config.put('unixSockPath', n);
  }
}
