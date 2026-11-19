import 'dart:io' as io;

import 'package:code_assets/code_assets.dart';
import 'package:data_assets/data_assets.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart';
import 'package:server/tray_asset.dart';

const _fs = LocalFileSystem();

Future<void> buildWakeMonitor(
  BuildInput input,
  BuildOutputBuilder output,
) async {
  if (!input.config.buildCodeAssets) return;
  if (input.config.code.targetOS != .macOS) return;

  final wakeMonitorDir = _fs.currentDirectory
      .childDirectory(input.packageRoot.path)
      .parent
      .childDirectory('clash_wake_monitor');
  final result = await io.Process.run('swift', [
    'build',
    '--package-path',
    wakeMonitorDir.path,
    '-c',
    'release',
    '--product',
    'ClashWakeMonitor',
  ]);
  if (result.exitCode != 0) {
    throw Exception('swift build failed: ClashWakeMonitor.\n${result.stderr}');
  }

  output.assets.code.add(
    CodeAsset(
      package: input.packageName,
      name: 'src/clash_wake_monitor_bindings_generated.dart',
      linkMode: DynamicLoadingBundled(),
      file: Uri.file(
        join(
          wakeMonitorDir.path,
          '.build',
          'release',
          'libClashWakeMonitor.dylib',
        ),
        windows: false,
      ),
    ),
  );

  final swiftSources = wakeMonitorDir.childDirectory('Sources');
  if (await swiftSources.exists()) {
    for (final item in swiftSources.listSync(recursive: true)) {
      if (item case File file) {
        output.dependencies.add(Uri.file(file.absolute.path));
      }
    }
  }
  output.dependencies.add(
    Uri.file(wakeMonitorDir.childFile('Package.swift').absolute.path),
  );
}

/// 在守护进程中运行的服务
Future<void> buildClashServer(
  BuildInput input,
  BuildOutputBuilder output,
) async {
  if (!input.config.buildDataAssets) return;

  if (!input.config.code.targetOS.isDesktop) return;

  final targetOs = input.config.code.targetOS;
  final arc = input.config.code.targetArchitecture;

  final packageName = input.packageName;

  final serverDir = _fs.currentDirectory;

  final result = await io.Process.run('dart', [
    'build',
    'cli',
  ], workingDirectory: serverDir.path);

  if (result.exitCode != 0) {
    throw Exception('dart build cli failed: server.\n${result.stderr}');
  }

  final exeDir = _fs.currentDirectory.childDirectory(
    join(serverDir.path, 'build', 'cli', '${targetOs}_$arc', 'bundle', 'bin'),
  );

  final clashLibDir = _fs.currentDirectory.childDirectory(
    join(serverDir.path, 'build', 'cli', '${targetOs}_$arc', 'bundle', 'lib'),
  );

  final libDir = serverDir.childDirectory('lib');
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

  final bins = await exeDir.list().toList();

  final suf = targetOs.dylibFileName('').split('.').last;
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

  if (targetOs == .macOS) {
    // 用户级状态栏程序：由 clashyService daemon 直接启动，app 退出后图标仍在。
    final trayDir = _fs.currentDirectory
        .childDirectory(input.packageRoot.path)
        .parent
        .childDirectory('clash_tray');
    final trayResult = await io.Process.run('swift', [
      'build',
      '--package-path',
      trayDir.path,
      '-c',
      'release',
      '--product',
      'ClashTray',
    ]);
    if (trayResult.exitCode != 0) {
      throw Exception('swift build failed: ClashTray.\n${trayResult.stderr}');
    }

    output.assets.data.add(
      DataAsset(
        package: packageName,
        name: clashTrayAssetName,
        file: Uri.file(
          join(trayDir.path, '.build', 'release', 'ClashTray'),
          windows: false,
        ),
      ),
    );

    final traySources = trayDir.childDirectory('Sources');
    if (await traySources.exists()) {
      for (final item in traySources.listSync(recursive: true)) {
        if (item case File file) {
          output.dependencies.add(Uri.file(file.absolute.path));
        }
      }
    }
    output.dependencies.add(
      Uri.file(trayDir.childFile('Package.swift').absolute.path),
    );
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
