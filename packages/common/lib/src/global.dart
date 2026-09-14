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
  }
}
