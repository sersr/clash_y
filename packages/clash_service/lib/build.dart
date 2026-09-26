import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:data_assets/data_assets.dart';
import 'package:hooks/hooks.dart';

import 'package:file/local.dart' as f;
import 'package:path/path.dart';

const fs = f.LocalFileSystem();

/// 注册守护进程 ffi
Future<void> buildMacOSDaemon(
  BuildInput input,
  BuildOutputBuilder output,
) async {
  if (!input.config.buildCodeAssets) return;

  if (input.config.code.targetOS != .macOS) return;
  final packageName = input.packageName;

  // 使用 swift build 编译 SPM 包
  final result = await Process.run('swift', [
    'build',
    '--package-path',
    'plugins/clash_service_drawin',
    '-c',
    'release',
  ], workingDirectory: input.packageRoot.path);

  if (result.exitCode != 0) {
    throw Exception('Swift build failed: ${result.stderr}');
  }

  // 定位编译产物 .dylib
  final dylibPath =
      '${input.packageRoot.path}/plugins/clash_service_drawin/.build/release/libclash-service.dylib';

  output.assets.code.add(
    CodeAsset(
      package: packageName,
      name: 'src/service/clash_service_macos.dart',
      linkMode: DynamicLoadingBundled(),
      file: Uri.file(dylibPath, windows: false),
    ),
  );
}

/// 在守护进程中运行的服务
Future<void> buildClashServer(
  BuildInput input,
  BuildOutputBuilder output,
) async {
  if (!input.config.buildDataAssets) return;

  final targetOs = input.config.code.targetOS;
  final arc = input.config.code.targetArchitecture;

  final packageName = input.packageName;

  final serverDir = fs.currentDirectory
      .childDirectory(input.packageRoot.path)
      .childDirectory('plugins')
      .childDirectory('server');

  final result = await Process.run('dart', [
    'build',
    'cli',
  ], workingDirectory: serverDir.path);

  if (result.exitCode != 0) {
    throw Exception('dart build cli failed: server.');
  }

  final name = targetOs.executableFileName('clashyService');
  final clashName = targetOs.dylibFileName('clash');

  final exePath = join(
    serverDir.path,
    'build',
    'cli',
    '${targetOs}_$arc',
    'bundle',
    'bin',
    name,
  );

  final clashPath = join(
    serverDir.path,
    'build',
    'cli',
    '${targetOs}_$arc',
    'bundle',
    'lib',
    clashName,
  );

  output.assets.data.add(
    DataAsset(
      package: packageName,
      name: 'bin/$name',
      file: Uri.file(exePath, windows: targetOs == .windows),
    ),
  );

  output.assets.data.add(
    DataAsset(
      package: packageName,
      name: 'lib/$clashName',
      file: Uri.file(clashPath, windows: targetOs == .windows),
    ),
  );
}
