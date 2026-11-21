import 'dart:io' as io;

import 'package:code_assets/code_assets.dart';
import 'package:data_assets/data_assets.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart';
import 'package:server/tray_asset.dart';

const _fs = LocalFileSystem();

/// 在守护进程中运行的服务
Future<void> buildClashServer(
  BuildInput input,
  BuildOutputBuilder output,
) async {
  if (!input.config.buildCodeAssets) return;

  if (!input.config.code.targetOS.isDesktop) return;

  final targetOs = input.config.code.targetOS;
  final arc = input.config.code.targetArchitecture;

  final packageName = input.packageName;

  final cmdRoot = _fs.currentDirectory
      .childDirectory(input.packageRoot.path)
      .parent
      .childDirectory('cmd');

  final result = await io.Process.run('dart', [
    'build',
    'cli',
  ], workingDirectory: cmdRoot.path);

  if (result.exitCode != 0) {
    throw Exception('dart build cli failed: cmd.\n${result.stderr}');
  }

  final bundleDir = cmdRoot
      .childDirectory('build')
      .childDirectory('cli')
      .childDirectory('${targetOs}_$arc')
      .childDirectory('bundle');

  final libDir = cmdRoot.childDirectory('lib');
  if (await libDir.exists()) {
    final list = await libDir.list(recursive: true).toList();
    for (var item in list) {
      if (item case File f) {
        if (f.basename.endsWith('.dart')) {
          output.dependencies.add(Uri.file(f.absolute.path));
        }
      }
    }
  }

  final suf = targetOs.dylibFileName('').split('.').last;
  final binDirs = [
    bundleDir.childDirectory('bin'),
    _fs.currentDirectory.childDirectory(
      join(cmdRoot.path, clashNativeBinDirRelativePath),
    ),
  ];
  for (final binDir in binDirs) {
    if (!await binDir.exists()) continue;
    final bins = await binDir.list().toList();
    for (var item in bins) {
      if (item case File f) {
        output.assets.data.add(
          DataAsset(
            package: packageName,
            name: 'bin/${f.basename}',
            file: Uri.file(item.path, windows: targetOs == .windows),
          ),
        );
      }
    }
  }

  final clashLibDir = bundleDir.childDirectory('lib');
  final libs = await clashLibDir.list().toList();

  for (var item in libs) {
    if (item case File f when f.basename.endsWith('.$suf')) {
      output.assets.data.add(
        DataAsset(
          package: packageName,
          name: 'lib/${f.basename}',
          file: Uri.file(item.path, windows: targetOs == .windows),
        ),
      );
    }
  }
}

Future<void> directoryCopy(Directory from, Directory to) async {
  final list = from.listSync();
  for (var item in list) {
    if (item is Directory) {
      final toDir = to.childDirectory(item.basename);
      toDir.createSync(recursive: true);
      await directoryCopy(item, toDir);
      continue;
    }
    if (item is File) {
      final toFile = to.childFile(item.basename);
      item.copySync(toFile.path);
    }
  }
}

extension on OS {
  bool get isDesktop {
    switch (this) {
      case .macOS || .windows || .linux:
        return true;
    }
    return false;
  }
}
