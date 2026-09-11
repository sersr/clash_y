import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

abstract final class G {
  static String? _appPath;
  static String get appPath => _appPath!;

  static Future<void> init() async {
    final docDir = await getApplicationDocumentsDirectory();
    _appPath = join(docDir.path, 'clash_y');
  }
}
