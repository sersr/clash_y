import 'dart:io' as io;

import 'package:code_assets/code_assets.dart';
import 'package:data_assets/data_assets.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:hooks/hooks.dart';
import 'package:path/path.dart' as p;
import 'package:server/tray_asset.dart';

const _fs = LocalFileSystem();

/// 构建并交付桌面端随包分发的原生二进制：`bin/clashyService`（Go 服务端，
/// 三平台都跑在特权账号下并自己创建 TUN），以及 macOS 的 `bin/clashyTray`
/// （用户会话里的菜单栏 Agent）。
///
/// 产物先落到 [clashNativeBinDirRelativePath]（稳定目录，仅内容变化时覆盖），
/// 再作为 DataAsset 交付，应用端按 `flutter_assets/packages/clash_service/bin/`
/// 取用。
Future<void> buildDesktopBinaries(
  BuildInput input,
  BuildOutputBuilder output,
) async {
  if (!input.config.buildCodeAssets) return;
  final targetOs = input.config.code.targetOS;
  if (!targetOs.isDesktop) return;

  final packageRoot = _fs.currentDirectory.childDirectory(
    input.packageRoot.toFilePath(),
  );
  final binDir = packageRoot.childDirectory(clashNativeBinDirRelativePath);
  binDir.createSync(recursive: true);

  await _buildService(input, packageRoot, binDir, targetOs, output);
  if (targetOs == .macOS) {
    await _buildTray(
      packageRoot,
      binDir,
      input.config.code.targetArchitecture,
      output,
    );
  }

  for (final item in binDir.listSync()) {
    if (item case File file) {
      output.assets.data.add(
        DataAsset(
          package: input.packageName,
          name: 'bin/${file.basename}',
          file: Uri.file(file.path, windows: targetOs == .windows),
        ),
      );
    }
  }
}

/// Go 服务端：`packages/clash_core/core/cmd` 的 main 包。
Future<void> _buildService(
  BuildInput input,
  Directory packageRoot,
  Directory binDir,
  OS targetOs,
  BuildOutputBuilder output,
) async {
  final coreDir = packageRoot.parent
      .childDirectory('clash_core')
      .childDirectory('core');
  final executableName = targetOs == .windows
      ? clashWindowsServiceExecutableName
      : clashServiceExecutableName;

  await _goBuild(
    coreDir: coreDir,
    packagePath: './cmd',
    executableName: executableName,
    binDir: binDir,
    targetOs: targetOs,
    architecture: input.config.code.targetArchitecture,
    cgo: cgoEnabled(input),
  );

  output.dependencies.add(Uri.file(coreDir.childFile('go.mod').absolute.path));
  output.dependencies.add(Uri.file(coreDir.childFile('go.sum').absolute.path));
  for (final item in coreDir.childDirectory('cmd').listSync(recursive: true)) {
    if (item case File file when file.basename.endsWith('.go')) {
      output.dependencies.add(Uri.file(file.absolute.path));
    }
  }
}

/// 桌面端 Go 二进制的编译标签。
///
/// `clashService.go` 的 `desktopTunOptions` 默认把 tun 栈设为 gvisor；sing-tun 在
/// 不带 `with_gvisor` 时编出来的是只返回 `ErrGVisorNotIncluded` 的桩，启动 TUN 会
/// 直接失败（`start tun: gVisor is not included in this build`）。
const goBuildTags = ['with_gvisor'];

/// 编译一个 Go 包到 [binDir]/[executableName]，返回目标文件。
Future<File> _goBuild({
  required Directory coreDir,
  required String packagePath,
  required String executableName,
  required Directory binDir,
  required OS targetOs,
  required Architecture architecture,
  required bool cgo,
}) async {
  final goArchitecture = switch (architecture) {
    Architecture.arm64 => 'arm64',
    Architecture.x64 => 'amd64',
    _ => throw UnsupportedError(
      'Unsupported desktop architecture: ${architecture.name}',
    ),
  };
  final goOperatingSystem = switch (targetOs) {
    OS.macOS => 'darwin',
    OS.linux => 'linux',
    OS.windows => 'windows',
    _ => throw UnsupportedError(
      'Unsupported desktop target OS: ${targetOs.name}',
    ),
  };

  final target = binDir.childFile(executableName);
  final temporary = binDir.childFile('$executableName.tmp');
  final executable = goExecutable();
  final arguments = [
    'build',
    '-trimpath',
    '-tags',
    goBuildTags.join(','),
    '-o',
    temporary.path,
    packagePath,
  ];
  final environment = goEnvironment(
    goOperatingSystem: goOperatingSystem,
    goArchitecture: goArchitecture,
    cgo: cgo,
  );
  final result = await io.Process.run(
    executable,
    arguments,
    workingDirectory: coreDir.path,
    environment: environment,
  );
  if (result.exitCode != 0) {
    throw io.ProcessException(
      executable,
      arguments,
      '${result.stdout}\n${result.stderr}',
      result.exitCode,
    );
  }
  _copyIfChanged(temporary, target);
  temporary.deleteSync();
  if (targetOs != .windows) {
    // 复制可能不保留可执行位，而 macOS 端要求随包二进制可执行且组/其他人不可写。
    final chmodResult = await io.Process.run('/bin/chmod', [
      '755',
      target.path,
    ]);
    if (chmodResult.exitCode != 0) {
      throw io.ProcessException(
        '/bin/chmod',
        ['755', target.path],
        '${chmodResult.stderr}',
        chmodResult.exitCode,
      );
    }
  }
  return target;
}

/// macOS 菜单栏托盘（Swift 包 `packages/clash_tray`）。
Future<void> _buildTray(
  Directory packageRoot,
  Directory binDir,
  Architecture architecture,
  BuildOutputBuilder output,
) async {
  final trayDir = packageRoot.parent.childDirectory('clash_tray');
  final tripleArchitecture = switch (architecture) {
    Architecture.arm64 => 'arm64',
    Architecture.x64 => 'x86_64',
    _ => throw UnsupportedError(
      'Unsupported macOS tray architecture: ${architecture.name}',
    ),
  };
  final triple = '$tripleArchitecture-apple-macosx12.0';

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
  final trayExecutable = binDir.childFile(clashTrayExecutableName);
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

/// 是否用 cgo 构建服务端与 TUN helper。
///
/// 默认关闭：这两个 Go 包的依赖图里没有任何 cgo 包，Windows 版本因此不需要 C
/// 工具链，产物也是单文件。需要 cgo 时（例如引入依赖 C 库的代码，或让 `net` 走
/// cgo 解析器）在根 `pubspec.yaml` 的 `hooks.user_defines` 里设
/// `clash_service: {cgo: true}`，或设置环境变量 `CLASHY_GO_CGO=1`。
bool cgoEnabled(BuildInput input) {
  final define = input.userDefines['cgo'];
  if (define is bool) return define;
  return io.Platform.environment['CLASHY_GO_CGO'] == '1';
}

/// 定位 `go` 可执行文件。
///
/// 从 IDE 或桌面图标启动的 Flutter 进程 PATH 往往只有系统目录，scoop 或官方安装
/// 的 Go 不在其中，所以按 `CLASHY_GO` → `GOROOT\bin` → 常见安装位置 → `PATH`
/// 顺序查找；都找不到时回退成裸 `go`，让错误信息由 Go 自己给出。
String goExecutable() {
  if (!io.Platform.isWindows) return 'go';

  final environment = io.Platform.environment;
  final explicitGo = environment['CLASHY_GO'];
  if (explicitGo != null && explicitGo.isNotEmpty) {
    final file = _fs.file(explicitGo);
    if (file.existsSync()) return file.path;
  }

  final candidates = <String>[];
  void addGo(String? path) {
    if (path != null && path.isNotEmpty) candidates.add(path);
  }

  addGo(
    environment['GOROOT'] == null
        ? null
        : p.join(environment['GOROOT']!, r'bin\go.exe'),
  );
  addGo(
    environment['USERPROFILE'] == null
        ? null
        : p.join(environment['USERPROFILE']!, r'scoop\shims\go.exe'),
  );
  addGo(
    environment['ProgramFiles'] == null
        ? null
        : p.join(environment['ProgramFiles']!, r'Go\bin\go.exe'),
  );
  addGo(
    environment['LOCALAPPDATA'] == null
        ? null
        : p.join(environment['LOCALAPPDATA']!, r'Programs\Go\bin\go.exe'),
  );

  for (final candidate in candidates) {
    final file = _fs.file(candidate);
    if (file.existsSync()) return file.path;
  }

  final searchPath = environment['PATH'];
  if (searchPath != null) {
    for (final directoryPath in searchPath.split(';')) {
      if (directoryPath.isEmpty) continue;
      final file = _fs.directory(directoryPath).childFile('go.exe');
      if (file.existsSync()) return file.path;
    }
  }
  return 'go';
}

/// 组装 `go build` 的环境变量。
///
/// Windows + cgo 时把 MSYS2 的 mingw-w64 工具链接进 PATH 并指定 `CC`：Go 只会把
/// `gcc` 交给链接器，编译器自己还需要同目录下的 cc1/as/ld。
Map<String, String> goEnvironment({
  required String goOperatingSystem,
  required String goArchitecture,
  required bool cgo,
}) {
  final environment = <String, String>{
    ...io.Platform.environment,
    'GOOS': goOperatingSystem,
    'GOARCH': goArchitecture,
    'CGO_ENABLED': cgo ? '1' : '0',
  };
  if (!cgo || goOperatingSystem != 'windows') {
    return environment;
  }

  final toolchain = findWindowsCToolchain();
  if (toolchain == null) {
    throw StateError(
      'cgo is enabled for the Windows build but no mingw-w64 gcc was found. '
      'Install MSYS2 with the mingw64 toolchain, or point CLASHY_CC at gcc.exe.',
    );
  }
  environment['CC'] = toolchain.compiler;
  final existingPath = environment['PATH'];
  environment['PATH'] = existingPath == null || existingPath.isEmpty
      ? toolchain.binDirectory
      : '${toolchain.binDirectory};$existingPath';
  return environment;
}

/// 一个可用于 cgo 的 Windows C 工具链。
class CToolchain {
  const CToolchain({required this.compiler, required this.binDirectory});

  /// `gcc.exe` 的绝对路径。
  final String compiler;

  /// 存放 cc1/as/ld 的目录，需要出现在 `PATH` 里。
  final String binDirectory;
}

/// MSYS2 里可用于 Windows 目标的工具链目录名。
///
/// `msys` 自身的 gcc 产出依赖 POSIX 运行时的程序，不能用于 Go 的 Windows 目标。
const windowsToolchainDirectories = ['mingw64', 'ucrt64', 'clang64'];

/// 查找 Windows 上可用的 mingw-w64 gcc。
///
/// 顺序：`CLASHY_CC` 显式指定 → MSYS2 环境变量 → 常见安装位置（含 scoop 的
/// `apps/msys2/current`）→ `PATH` 上的 `gcc`。
CToolchain? findWindowsCToolchain() {
  final environment = io.Platform.environment;

  final explicitCompiler = environment['CLASHY_CC'];
  if (explicitCompiler != null && explicitCompiler.isNotEmpty) {
    final file = _fs.file(explicitCompiler);
    if (file.existsSync()) {
      return CToolchain(compiler: file.path, binDirectory: file.parent.path);
    }
  }

  final roots = <String>[];
  void addRoot(String? path) {
    if (path != null && path.isNotEmpty) roots.add(path);
  }

  addRoot(environment['MSYS2_ROOT']);
  addRoot(environment['MINGW_HOME']);
  roots.add(r'C:\msys64');
  roots.add(r'C:\msys2');
  roots.add(r'C:\tools\msys64');
  final home = environment['USERPROFILE'];
  if (home != null && home.isNotEmpty) {
    // scoop 把 MSYS2 装在 `apps\msys2\current`。
    addRoot(p.join(home, r'scoop\apps\msys2\current'));
  }
  final localAppData = environment['LOCALAPPDATA'];
  if (localAppData != null && localAppData.isNotEmpty) {
    addRoot(p.join(localAppData, r'Programs\msys64'));
    addRoot(p.join(localAppData, 'msys64'));
  }

  for (final root in roots) {
    for (final directoryName in windowsToolchainDirectories) {
      // gcc.exe 在 `<环境>\bin` 下，同目录还有 cc1/as/ld。
      final toolchain = _toolchainAt(p.join(root, directoryName, 'bin'));
      if (toolchain != null) return toolchain;
    }
    // MINGW_HOME 常常直接指向 `...\mingw64`，此时 `root\bin` 才是工具链目录。
    final toolchain = _toolchainAt(p.join(root, 'bin')) ?? _toolchainAt(root);
    if (toolchain != null) return toolchain;
  }

  final searchPath = environment['PATH'];
  if (searchPath != null) {
    for (final directoryPath in searchPath.split(';')) {
      if (directoryPath.isEmpty) continue;
      final toolchain = _toolchainAt(directoryPath);
      if (toolchain != null) return toolchain;
    }
  }
  return null;
}

CToolchain? _toolchainAt(String directoryPath) {
  final compiler = _fs.directory(directoryPath).childFile('gcc.exe');
  if (!compiler.existsSync()) return null;
  return CToolchain(compiler: compiler.path, binDirectory: directoryPath);
}

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

/// 把原生二进制目录里的文件作为 `bin/*` 数据资产交付。
///
/// `OS.isDesktop` 之外的目标（Android、iOS）由各自平台的实现负责。
extension on OS {
  bool get isDesktop {
    switch (this) {
      case .macOS || .windows || .linux:
        return true;
    }
    return false;
  }
}
