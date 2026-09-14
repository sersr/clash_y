import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:data_assets/data_assets.dart';
import 'package:hooks/hooks.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets && !input.config.buildDataAssets) {
      return;
    }

    final code = input.config.code;
    final targetOs = code.targetOS;
    final targetArchitecture = _goArchitecture(code.targetArchitecture);
    final goDirectory = Platform.isAndroid ?  input.packageRoot.resolve('core/'): input.packageRoot.resolve('../mihomo/');
    final outputName = targetOs == OS.android ? 'libclash.so' : 'clash';
    final outputPath = input.outputDirectory.resolve(outputName);

    output.dependencies.add(goDirectory);
    output.dependencies.add(goDirectory.resolve('go.mod'));

    final path = Platform.environment['PATH'] != null
        ? ':${Platform.environment['PATH']}'
        : '';

    final environment = <String, String>{
      'CGO_ENABLED': '1',
      'GOOS': _goOperatingSystem(targetOs),
      'GOARCH': targetArchitecture,
      'PATH': path,
    };
    final compiler = code.cCompiler?.compiler;
    if (compiler != null) {
      final compilerPath = compiler.toFilePath();
      if (targetOs == OS.android) {
        final target = _androidTarget(
          code.targetArchitecture,
          code.android.targetNdkApi,
        );
        environment['CC'] = '$compilerPath --target=$target';
      } else {
        environment['CC'] = compilerPath;
      }
    }
    if (targetOs == OS.macOS && Platform.isMacOS) {
      final sdkResult = await Process.run('xcrun', [
        '--sdk',
        'macosx',
        '--show-sdk-path',
      ]);
      if (sdkResult.exitCode == 0) {
        environment['SDKROOT'] = (sdkResult.stdout as String).trim();
      }
    }

    final arguments = <String>[
      'build',
      if (targetOs == OS.android) '-buildmode=c-shared',
      '-trimpath',
      '-o',
      outputPath.toFilePath(),
      '-tags',
      'with_gvisor',
      '.',
    ];

    final result = await Process.run(
      'go',
      arguments,
      workingDirectory: goDirectory.toFilePath(),
      environment: environment,
    );
    if (result.exitCode != 0) {
      // return;
      throw ProcessException(
        'go',
        arguments,
        '${result.stdout}\n${result.stderr}',
        result.exitCode,
      );
    }

    if (targetOs == OS.android) {
      output.assets.code.add(
        CodeAsset(
          package: input.packageName,
          name: outputName,
          file: outputPath,
          linkMode: DynamicLoadingBundled(),
        ),
      );
    } else if (input.config.buildDataAssets) {
      output.assets.data.add(
        DataAsset(
          package: input.packageName,
          name: outputName,
          file: outputPath,
        ),
      );
    }
  });
}

String _goArchitecture(Architecture architecture) => switch (architecture) {
  Architecture.arm => 'arm',
  Architecture.arm64 => 'arm64',
  Architecture.ia32 => '386',
  Architecture.x64 => 'amd64',
  Architecture.riscv32 => 'riscv32',
  Architecture.riscv64 => 'riscv64',
  _ => throw UnsupportedError(
    'Unsupported Go architecture: ${architecture.name}',
  ),
};

String _goOperatingSystem(OS operatingSystem) => switch (operatingSystem) {
  OS.macOS => 'darwin',
  final os => os.name,
};

String _androidTarget(Architecture architecture, int api) =>
    switch (architecture) {
      Architecture.arm => 'armv7a-linux-androideabi$api',
      Architecture.arm64 => 'aarch64-linux-android$api',
      Architecture.ia32 => 'i686-linux-android$api',
      Architecture.x64 => 'x86_64-linux-android$api',
      Architecture.riscv64 => 'riscv64-linux-android$api',
      _ => throw UnsupportedError(
        'Unsupported Android architecture: ${architecture.name}',
      ),
    };
