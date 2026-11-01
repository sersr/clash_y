import 'package:common/src/hive.dart';
import 'package:meta/meta.dart';
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
