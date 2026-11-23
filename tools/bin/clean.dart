import 'dart:io';

import 'package:file/file.dart';
import 'package:file/local.dart';

const fs = LocalFileSystem();

void main(List<String> args) async {
  final hasCache = args.contains('cache');

  final packages = fs.currentDirectory.childDirectory('packages');

  for (var item in packages.listSync()) {
    if (item is! Directory) continue;
    final build = item.childDirectory('build');
    final dotBuild = item.childDirectory('.build');
    if (build.existsSync()) {
      await build.delete(recursive: true);
    }
    if (dotBuild.existsSync()) {
      await dotBuild.delete(recursive: true);
    }
  }
  if (!hasCache) await Process.run('flutter', ['clean']);
}
