import 'dart:io' as io;

import 'package:code_assets/code_assets.dart';
import 'package:data_assets/data_assets.dart';
import 'package:file/file.dart';
import 'package:file/local.dart' as f;
import 'package:hooks/hooks.dart';
import 'package:path/path.dart';

const fs = f.LocalFileSystem();

extension on HookInputUserDefines {
  bool get isCli {
    return this['isCli'] == true;
  }
}

/// 注册守护进程 ffi
Future<void> buildMacOSDaemon(
  BuildInput input,
  BuildOutputBuilder output,
) async {
  if (!input.config.buildCodeAssets) return;

  if (input.config.code.targetOS != .macOS) return;
  final isCli = input.userDefines.isCli;
  if (isCli) {
    print("ignore");
    return;
  }

  final packageName = input.packageName;

  // 使用 swift build 编译 SPM 包
  final result = await io.Process.run('swift', [
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

  if (input.userDefines.isCli) return;

  final targetOs = input.config.code.targetOS;
  final arc = input.config.code.targetArchitecture;

  final packageName = input.packageName;

  final serverDir = fs.currentDirectory
      .childDirectory(input.packageRoot.path)
      .childDirectory('plugins')
      .childDirectory('server');

  final result = await io.Process.run('dart', [
    'build',
    'cli',
  ], workingDirectory: serverDir.path);

  if (result.exitCode != 0) {
    throw Exception('dart build cli failed: server.\n${result.stderr}');
  }

  final name = targetOs.executableFileName('clashyService');
  final clashName = targetOs.dylibFileName('clash');
  // final bundle = fs.currentDirectory.childDirectory(
  //   join(serverDir.path, 'build', 'cli', '${targetOs}_$arc', 'bundle'),
  // );

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

  // if (bundle.existsSync()) {
  //   final clashService = bundle.parent.childDirectory('ClashService');
  //   clashService.createSync(recursive: true);
  //   copy(bundle, clashService);
  // }

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

Future<void> copy(Directory from, Directory to) async {
  final list = from.listSync();
  for (var item in list) {
    if (item is Directory) {
      final toDir = to.childDirectory(item.basename);
      toDir.createSync(recursive: true);
      await copy(item, toDir);
      continue;
    }
    if (item is File) {
      final toFile = to.childFile(item.basename);
      item.copySync(toFile.path);
    }
  }
}

/// 在守护进程中运行的服务
Future<void> buildWindowsDll(
  BuildInput input,
  BuildOutputBuilder output,
) async {
  if (!input.config.buildDataAssets) return;
  if (!input.userDefines.isCli) {
    return;
  }

  final targetOs = input.config.code.targetOS;

  if (targetOs != .windows) return;

  output.assets.code.add(
    .new(
      package: input.packageName,
      name: 'src/service/clash_service_windows.dart',
      linkMode: DynamicLoadingBundled(),
      file: Uri.file(
        join(input.packageRoot.path, 'bin', 'WindowsServiceDLL64.dll'),
      ),
    ),
  );
}
