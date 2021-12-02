import 'package:clash_window_dll/clash_window_dll.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'pages/app.dart';
import 'package:useful_tools/useful_tools.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart';

void main() {
  Log.logRun(() async {
    NopWidgetsFlutterBinding.ensureInitialized();
    final appDir = await getApplicationDocumentsDirectory();
    Hive.init(join(appDir.path, 'clash_y', 'configs'));
    ClashWindowDll.setHideOnClose(true);
    runApp(const MultiProviders());
  });
}
