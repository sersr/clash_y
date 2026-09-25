import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart';

Future<void> buildClash(BuildInput input, BuildOutputBuilder output) async {
  final code = input.config.code;
  final targetOs = code.targetOS;

  final targetArchitecture = _goArchitecture(code.targetArchitecture);
  final goDirectory = targetOs == OS.android
      ? input.packageRoot.resolve('core/')
      : input.packageRoot.resolve('../mihomo/');
  final outputName = targetOs == OS.android ? 'libclash.so' : 'clash';
  var outputPath = input.outputDirectory.resolve(outputName).path;

  if (targetOs != .android) {
    outputPath = join(
      input.packageRoot.path,
      'build',
      targetOs.name,
      outputName,
    );
  }

  input.config.json;
  output.dependencies.add(goDirectory);
  output.dependencies.add(goDirectory.resolve('go.mod'));
  if (targetOs == OS.android) {
    output.dependencies.add(goDirectory.resolve('jni_android.go'));
    output.dependencies.add(goDirectory.resolve('jni_android.c'));
  }

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

  // `cmfa` selects the VpnService friendly TUN implementation: sing-tun then
  // adopts the file descriptor handed over by the Android app instead of
  // creating and routing a tun device of its own, which needs root.
  final tags = <String>['with_gvisor', if (targetOs == OS.android) 'cmfa'];

  final arguments = <String>[
    'build',
    if (targetOs == OS.android) '-buildmode=c-shared',
    '-trimpath',
    '-o',
    outputPath,
    '-tags',
    tags.join(','),
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
        file: .parse(outputPath),
        linkMode: DynamicLoadingBundled(),
      ),
    );
  }
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
