import 'package:file/file.dart';
import 'package:file/local.dart';

const fs = LocalFileSystem();

void main() async {
  final packages = fs.currentDirectory.childDirectory('packages');

  final core = packages.childDirectory('clash_core');
  final clashServiceAndroid = packages.childDirectory('clash_service_android');
  final clashTray = packages.childDirectory('clash_tray');
  final clashWakeMonitor = packages.childDirectory('clash_wake_monitor');
  final server = packages.childDirectory('server');
  final list = <FileSystemEntity>[];

  list.add(core.childDirectory('build'));
  list.add(clashServiceAndroid.childDirectory('.build'));

  list.add(clashWakeMonitor.childDirectory('.build'));
  list.add(clashTray.childDirectory('.build'));
  list.add(server.childDirectory('build'));

  for (var item in list) {
    if (await item.exists()) await item.delete(recursive: true);
  }
}
