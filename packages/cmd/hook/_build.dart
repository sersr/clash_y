import 'dart:io' as io;

import 'package:code_assets/code_assets.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart';

import 'package:server/tray_asset.dart';

const _fs = LocalFileSystem();

Directory _nativeBinDir(Directory cmdRoot) => cmdRoot
    .childDirectory('build')
    .childDirectory('native')
    .childDirectory('bin');

/// 仅在内容变化时覆盖，避免每次构建都更新 mtime 导致 hook 缓存失效。
void _copyIfChanged(File source, File target) {
  final sourceBytes = source.readAsBytesSync();
  if (target.existsSync()) {
    final targetBytes = target.readAsBytesSync();
    if (_bytesEqual(sourceBytes, targetBytes)) return;
  }
  source.copySync(target.path);
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Future<void> buildWakeMonitor(
  BuildInput input,
  BuildOutputBuilder output,
) async {
  if (!input.config.buildCodeAssets) return;
  if (input.config.code.targetOS != .macOS) return;

  final wakeMonitorDir = _fs.currentDirectory
      .childDirectory(input.packageRoot.toFilePath())
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

Future<void> buildTrayExecutable(
  BuildInput input,
  BuildOutputBuilder output,
) async {
  if (!input.config.buildCodeAssets) return;
  if (input.config.code.targetOS != .macOS) return;

  final cmdRoot = _fs.currentDirectory.childDirectory(
    input.packageRoot.toFilePath(),
  );
  final architecture = switch (input.config.code.targetArchitecture) {
    Architecture.arm64 => 'arm64',
    Architecture.x64 => 'x86_64',
    _ => throw UnsupportedError(
      'Unsupported macOS tray architecture: '
      '${input.config.code.targetArchitecture.name}',
    ),
  };
  final triple = '$architecture-apple-macosx12.0';
  final trayDir = cmdRoot.parent.childDirectory('clash_tray');
  final result = await io.Process.run('swift', [
    'build',
    '--package-path',
    trayDir.path,
    '--triple',
    triple,
    '-c',
    'release',
    '--product',
    'ClashTray',
  ]);
  if (result.exitCode != 0) {
    throw Exception('swift build failed: ClashTray.\n${result.stderr}');
  }

  final binPathResult = await io.Process.run('swift', [
    'build',
    '--package-path',
    trayDir.path,
    '--triple',
    triple,
    '-c',
    'release',
    '--show-bin-path',
  ]);
  if (binPathResult.exitCode != 0) {
    throw Exception(
      'swift build failed to locate ClashTray output.\n'
      '${binPathResult.stderr}',
    );
  }
  final sourceExecutable = _fs
      .directory((binPathResult.stdout as String).trim())
      .childFile('ClashTray');
  final exeDir = _nativeBinDir(cmdRoot);
  exeDir.createSync(recursive: true);
  final trayExecutable = exeDir.childFile(clashTrayExecutableName);
  _copyIfChanged(sourceExecutable, trayExecutable);
  final chmodResult = await io.Process.run('/bin/chmod', [
    '755',
    trayExecutable.path,
  ]);
  if (chmodResult.exitCode != 0) {
    throw io.ProcessException(
      '/bin/chmod',
      ['755', trayExecutable.path],
      '${chmodResult.stderr}',
      chmodResult.exitCode,
    );
  }
  output.dependencies.add(Uri.file(trayExecutable.absolute.path));

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

/// 在守护进程中运行的服务
Future<void> buildClashServer(
  BuildInput input,
  BuildOutputBuilder output,
) async {
  if (!input.config.buildCodeAssets) return;

  if (!input.config.code.targetOS.isDesktop) return;

  final targetOs = input.config.code.targetOS;
  final arc = input.config.code.targetArchitecture;

  final cmdRoot = _fs.currentDirectory.childDirectory(
    input.packageRoot.toFilePath(),
  );

  final exeDir = _nativeBinDir(cmdRoot);

  final goArchitecture = switch (arc) {
    Architecture.arm64 => 'arm64',
    Architecture.x64 => 'amd64',
    _ => throw UnsupportedError(
      'Unsupported TUN helper architecture: ${arc.name}',
    ),
  };
  final goOperatingSystem = switch (targetOs) {
    OS.macOS => 'darwin',
    OS.linux => 'linux',
    OS.windows => 'windows',
    _ => throw UnsupportedError(
      'Unsupported TUN helper target OS: ${targetOs.name}',
    ),
  };
  final coreDir = cmdRoot.parent
      .childDirectory('clash_core')
      .childDirectory('core');
  final helperFileName = clashTunHelperFileName(
    windows: targetOs == OS.windows,
  );
  final helperPath = exeDir.childFile(helperFileName);
  helperPath.parent.createSync(recursive: true);
  final tempHelperPath = helperPath.parent.childFile('$helperFileName.tmp');
  final helperArguments = [
    'build',
    '-trimpath',
    '-o',
    tempHelperPath.path,
    './cmd/clashy_tun_helper',
  ];
  final helperResult = await io.Process.run(
    'go',
    helperArguments,
    workingDirectory: coreDir.path,
    environment: {
      ...io.Platform.environment,
      'CGO_ENABLED': '0',
      'GOOS': goOperatingSystem,
      'GOARCH': goArchitecture,
    },
  );
  if (helperResult.exitCode != 0) {
    throw io.ProcessException(
      'go',
      helperArguments,
      '${helperResult.stdout}\n${helperResult.stderr}',
      helperResult.exitCode,
    );
  }
  _copyIfChanged(tempHelperPath, helperPath);
  tempHelperPath.deleteSync();
  output.dependencies.add(Uri.file(helperPath.absolute.path));

  output.dependencies.add(Uri.file(coreDir.childFile('go.mod').absolute.path));
  output.dependencies.add(Uri.file(coreDir.childFile('go.sum').absolute.path));
  for (final sourceDirectory in [
    coreDir.childDirectory('tunbroker'),
    coreDir.childDirectory('cmd').childDirectory('clashy_tun_helper'),
  ]) {
    for (final item in sourceDirectory.listSync(recursive: true)) {
      if (item case File file) {
        output.dependencies.add(Uri.file(file.absolute.path));
      }
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
