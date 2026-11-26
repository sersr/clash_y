import 'dart:io';

import 'package:file/file.dart';
import 'package:file/local.dart';

const fs = LocalFileSystem();

/// Native copies the Android build carries over between runs.
///
/// Gradle keeps these between builds, so after the Go core changed,
/// `flutter build` can still package an old `libclash.so` — the app then runs
/// the previous core while the source looks updated. Removing them forces a
/// copy from the freshly built hook output.
const _nativeCopies = <String>[
  'build/app/intermediates/flutter/debug/native_assets',
  'build/app/intermediates/flutter/release/native_assets',
  'build/app/intermediates/flutter/profile/native_assets',
  'build/app/generated/jniLibs',
  'build/app/intermediates/merged_native_libs',
  'build/app/intermediates/merged_jni_libs',
  'build/app/intermediates/stripped_native_libs',
];

void main(List<String> args) {
  final hasCache = args.contains('cache');
  final isDry = args.contains('dry');

  final root = _repositoryRoot();

  _cleanPackages(root.childDirectory('packages'), isDry);
  _cleanNativeCopies(root, isDry);
  _cleanStaleHookBuilds(root, isDry);

  if (!hasCache && !isDry) {
    Process.runSync('flutter', ['clean'], runInShell: true);
  }
}

/// Resolves the repository root so the script also works from `tools/`.
Directory _repositoryRoot() {
  var dir = fs.currentDirectory;
  while (dir.path != dir.parent.path) {
    if (dir.childDirectory('packages').existsSync() &&
        dir.childDirectory('lib').existsSync()) {
      return dir;
    }
    dir = dir.parent;
  }
  return fs.currentDirectory;
}

/// Drops the packages' own build outputs, as before.
void _cleanPackages(Directory packages, bool isDry) {
  if (!packages.existsSync()) return;
  for (var item in packages.listSync()) {
    if (item is! Directory) continue;
    _remove(item.childDirectory('build'), isDry);
    _remove(item.childDirectory('.build'), isDry);
  }
}

void _cleanNativeCopies(Directory root, bool isDry) {
  for (final path in _nativeCopies) {
    _remove(root.childDirectory(path), isDry);
  }
}

/// Keeps only the newest Go core build per hook package.
///
/// `hooks_runner` names each build after a content hash, so the directory
/// grows with every core change and the older ones only take disk space.
void _cleanStaleHookBuilds(Directory root, bool isDry) {
  final shared = root.childDirectory('.dart_tool/hooks_runner/shared');
  if (!shared.existsSync()) return;

  for (var package in shared.listSync()) {
    if (package is! Directory) continue;
    final build = package.childDirectory('build');
    if (!build.existsSync()) continue;

    final builds = build.listSync().whereType<Directory>().toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    for (final stale in builds.skip(1)) {
      _remove(stale, isDry);
    }
  }
}

void _remove(Directory dir, bool isDry) {
  if (!dir.existsSync()) return;
  final size = _sizeOf(dir);
  if (isDry) {
    stdout.writeln('[dry] ${dir.path} (${_human(size)})');
    return;
  }
  dir.deleteSync(recursive: true);
  stdout.writeln('[clean] ${dir.path} (${_human(size)})');
}

int _sizeOf(Directory dir) {
  var total = 0;
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    try {
      total += entity.lengthSync();
    } catch (_) {
      // A file removed while walking the tree is not worth failing over.
    }
  }
  return total;
}

String _human(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(value >= 100 || unit == 0 ? 0 : 1)}${units[unit]}';
}
