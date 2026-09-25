import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

Future<void> buildMacOS(BuildInput input, BuildOutputBuilder output) async {
  if (input.config.code.targetOS != .macOS) return;
  final packageName = input.packageName;

  // 使用 swift build 编译 SPM 包
  final result = await Process.run('swift', [
    'build',
    '--package-path',
    'plugins/vpn_service',
    '-c',
    'release',
  ], workingDirectory: input.packageRoot.path);

  if (result.exitCode != 0) {
    throw Exception('Swift build failed: ${result.stderr}');
  }

  // 定位编译产物 .dylib
  final dylibPath =
      '${input.packageRoot.path}/plugins/vpn_service/.build/release/libvpn-service.dylib';

  output.assets.code.add(
    CodeAsset(
      package: packageName,
      name: 'src/service/vpn_service_macos_ffi.dart',
      linkMode: DynamicLoadingBundled(),
      file: Uri.file(dylibPath, windows: false),
    ),
  );
}
