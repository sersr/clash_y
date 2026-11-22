import 'dart:io';

import 'package:file/file.dart';
import 'package:file/local.dart';

const fs = LocalFileSystem();

void main() async {
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
  await Process.run('flutter', ['clean']);
}
