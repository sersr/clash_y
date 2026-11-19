import 'dart:io' as io;

import 'package:code_assets/code_assets.dart';
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

Future<void> buildTrayExecutable(
  BuildInput input,
  BuildOutputBuilder output,
) async {
  if (!input.config.buildCodeAssets) return;
  if (input.config.code.targetOS != .macOS) return;

  final serverDir = _fs.currentDirectory.childDirectory(input.packageRoot.path);
  final targetOs = input.config.code.targetOS;
  final architecture = switch (input.config.code.targetArchitecture) {
    Architecture.arm64 => 'arm64',
    Architecture.x64 => 'x86_64',
    _ => throw UnsupportedError(
      'Unsupported macOS tray architecture: '
      '${input.config.code.targetArchitecture.name}',
    ),
  };
  final triple = '$architecture-apple-macosx12.0';
  final trayDir = _fs.currentDirectory
      .childDirectory(input.packageRoot.path)
      .parent
      .childDirectory('clash_tray');
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
  final exeDir = serverDir
      .childDirectory('build')
      .childDirectory('cli')
      .childDirectory('${targetOs}_${input.config.code.targetArchitecture}')
      .childDirectory('bundle')
      .childDirectory('bin');
  exeDir.createSync(recursive: true);
  final trayExecutable = exeDir.childFile(clashTrayExecutableName);
  sourceExecutable.copySync(trayExecutable.path);
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

  final serverDir = _fs.currentDirectory.childDirectory(input.packageRoot.path);

  final exeDir = _fs.currentDirectory.childDirectory(
    join(serverDir.path, 'build', 'cli', '${targetOs}_$arc', 'bundle', 'bin'),
  );

  if (targetOs == .macOS) {
    final goArchitecture = switch (arc) {
      Architecture.arm64 => 'arm64',
      Architecture.x64 => 'amd64',
      _ => throw UnsupportedError(
        'Unsupported macOS helper architecture: ${arc.name}',
      ),
    };
    final coreDir = serverDir.parent
        .childDirectory('clash_core')
        .childDirectory('core');
    final helperPath = exeDir.childFile('clashyTunHelper');
    helperPath.parent.createSync(recursive: true);
    final helperArguments = [
      'build',
      '-trimpath',
      '-o',
      helperPath.path,
      './cmd/clashy_tun_helper',
    ];
    final helperResult = await io.Process.run(
      'go',
      helperArguments,
      workingDirectory: coreDir.path,
      environment: {
        ...io.Platform.environment,
        'CGO_ENABLED': '0',
        'GOOS': 'darwin',
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

    output.dependencies.add(
      Uri.file(coreDir.childFile('go.mod').absolute.path),
    );
    output.dependencies.add(
      Uri.file(coreDir.childFile('go.sum').absolute.path),
    );
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
