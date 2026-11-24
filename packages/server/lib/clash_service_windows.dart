import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'tray_asset.dart';

const windowService = 'clashy_service';

/// 特权 TUN helper 的 Windows 服务名，与 Go 侧
/// `clashService_windows.go`/`tunbroker` 保持一致。
const windowTunHelperService = 'clashy_tun_helper';

const _description = 'Clash VPN';

/// 安装服务（未提权时弹 UAC 密码框，与 Linux pkexec 对等）。
///
/// 用 `sc create/config` 写入服务配置，行为对应其他平台的 install：
/// - 开机自启（start= auto + DelayedAutostart，与原实现一致）
/// - 故障自动重启 5 次、间隔 5s、60s 内计数（对应 systemd 的
///   `Restart=on-failure` / `RestartSec=5` / `StartLimitBurst=5`）
///
/// 同一份脚本顺带注册特权 TUN helper（`clashy_tun_helper`，以 LocalSystem
/// 运行）：服务在开机时就已具备 Wintun 能力，且 helper 的安装与应用安装共用
/// 同一次 UAC 授权。
///
/// 幂等：返回服务当前是否存在；用户取消 UAC 返回 false。
Future<bool> installService() async {
  final code = await _runElevated(_installScript());
  if (code == errorCancelled) return false;
  return _serviceExists();
}

/// 启动服务（未安装时先安装）。单次 UAC 完成安装+启动。
///
/// 返回服务是否处于运行状态。
Future<bool> startService() async {
  final code = await _runElevated(
    '${_installScript()}sc start $windowService\n',
  );
  if (code == errorCancelled) return false;
  for (var i = 0; i < 50 && !isServiceRunning(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  final running = isServiceRunning();
  if (!running) {
    final query = Process.runSync('sc', ['query', windowService]);
    final config = Process.runSync('sc', ['qc', windowService]);
    throw StateError(
      'Failed to start Windows clashyService: elevated script exit code '
      '$code; sc query exit code ${query.exitCode}; '
      '${query.stdout} ${query.stderr}; '
      'sc qc exit code ${config.exitCode}; ${config.stdout} ${config.stderr}',
    );
  }
  return running;
}

/// 停止服务（保留已安装状态）。需要时弹 UAC；未安装/已停止时不弹。
///
/// 返回服务是否已停止。
Future<bool> stopService() async {
  if (_serviceState() == null) return true; // 未安装视为已停止
  final code = await _runElevated('sc stop $windowService\n');
  if (code == errorCancelled) return false;
  for (var i = 0; i < 50; i++) {
    final s = _serviceState();
    if (s == null || s == 1) return true; // 服务不存在或已停止
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  return _serviceState() == 1;
}

/// 卸载服务。停止 + `sc delete`，单次 UAC。
///
/// 同时卸载特权 TUN helper（它随应用安装，也随应用卸载）。并清理旧 DLL 实现
/// 残留的 EventLog 注册。
/// 返回服务是否已不存在；用户取消 UAC 返回 false。
Future<bool> uninstallService() async {
  if (!_serviceExists()) return true;
  const script =
      '''
sc stop $windowService >nul 2>&1
for /l %%i in (1,1,30) do (
  sc query $windowService >nul 2>&1 || goto :del
  sc query $windowService | findstr /c:"STOPPED" >nul && goto :del
  timeout /t 1 /nobreak >nul
)
:del
sc delete $windowService >nul 2>&1
reg delete "HKLM\\SYSTEM\\CurrentControlSet\\Services\\EventLog\\Application\\$windowService" /f >nul 2>&1
sc stop $windowTunHelperService >nul 2>&1
for /l %%i in (1,1,20) do (
  sc query $windowTunHelperService >nul 2>&1 || goto :delHelper
  sc query $windowTunHelperService | findstr /c:"STOPPED" >nul && goto :delHelper
  timeout /t 1 /nobreak >nul
)
:delHelper
sc delete $windowTunHelperService >nul 2>&1
''';
  final code = await _runElevated(script);
  if (code == errorCancelled) return false;
  for (var i = 0; i < 10; i++) {
    // sc delete 后服务可能短暂处于 marked-for-deletion
    if (!_serviceExists()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return !_serviceExists();
}

/// 服务是否处于运行状态（4=RUNNING，2=START_PENDING）。查询无需提权。
bool isServiceRunning() {
  final s = _serviceState();
  return s == 4 || s == 2;
}

/// 服务是否已安装。查询无需提权。
bool isServiceInstalled() => _serviceExists();

/// install 脚本（不含 start），行为见 [installService]。
String _installScript() {
  final raw = p.join(
    p.dirname(Platform.resolvedExecutable),
    'data',
    'flutter_assets',
    clashServiceAssetPackagePath,
    'bin',
    clashWindowsServiceExecutableName,
  );
  if (!File(raw).existsSync()) {
    throw StateError('Bundled Windows clashyService is missing: $raw');
  }
  // 含空格时 binPath 的值本身需带引号，否则 SCM 拆分导致启动失败
  final binPath = raw.contains(' ') ? '"\\"$raw\\""' : raw;

  final helperRaw = p.join(p.dirname(raw), clashTunHelperWindowsExecutableName);
  if (!File(helperRaw).existsSync()) {
    throw StateError('Bundled Windows TUN helper is missing: $helperRaw');
  }
  final helperBinPath = helperRaw.contains(' ')
      ? '"\\"$helperRaw\\""'
      : helperRaw;

  return 'sc ${_serviceExists() ? 'config' : 'create'} $windowService '
      'binPath= $binPath start= auto obj= "LocalSystem"\n'
      'sc description $windowService "$_description"\n'
      'sc failure $windowService reset= 60 '
      'actions= restart/5000/restart/5000/restart/5000/restart/5000/restart/5000\n'
      'reg add "HKLM\\SYSTEM\\CurrentControlSet\\Services\\$windowService" '
      '/v DelayedAutostart /t REG_DWORD /d 1 /f\n'
      // TUN helper 由 SYSTEM 运行，服务端只连它的命名管道。create 在服务已存在
      // 时报错并被丢弃，紧跟的 config 负责更新 binPath 与启动类型。
      'sc create $windowTunHelperService binPath= $helperBinPath start= auto '
      '>nul 2>&1\n'
      'sc config $windowTunHelperService binPath= $helperBinPath start= auto\n'
      'sc description $windowTunHelperService "Clashy TUN Helper"\n'
      'sc failure $windowTunHelperService reset= 60 '
      'actions= restart/5000/restart/5000/restart/5000/restart/5000/restart/5000\n'
      'sc start $windowTunHelperService >nul 2>&1\n';
}

bool _serviceExists() {
  final r = Process.runSync('sc', ['query', windowService]);
  return r.exitCode == 0;
}

/// 读取 `sc query` 的 STATE 数字（数字与系统语言无关）。
///
/// 1=STOPPED 2=START_PENDING 3=STOP_PENDING 4=RUNNING；服务不存在返回 null。
int? _serviceState() {
  final r = Process.runSync('sc', ['query', windowService]);
  if (r.exitCode != 0) return null;
  final m = RegExp(r'STATE\s*:\s*(\d+)').firstMatch(r.stdout as String);
  return m == null ? null : int.parse(m.group(1)!);
}

// ==================== UAC 提权（ShellExecuteEx runas） ====================
//
// 与 Linux(pkexec)/macOS(osascript administrator) 对等：进程未提权时
// 弹出系统 UAC 密码框，以管理员权限执行管理脚本；用户取消返回
// [errorCancelled]（ERROR_CANCELLED）。

/// ERROR_CANCELLED：用户取消了 UAC 弹窗。
const errorCancelled = 1223;

final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _shell32 = DynamicLibrary.open('shell32.dll');
final _advapi = DynamicLibrary.open('advapi32.dll');

bool? _elevatedCache;
bool _isElevated() => _elevatedCache ??= _queryElevated();

bool _queryElevated() {
  final getCurrentProcess = _kernel32
      .lookup<NativeFunction<Pointer<Void> Function()>>('GetCurrentProcess')
      .asFunction<Pointer<Void> Function()>();
  final openProcessToken = _advapi
      .lookup<
        NativeFunction<
          Int32 Function(Pointer<Void>, Uint32, Pointer<Pointer<Void>>)
        >
      >('OpenProcessToken')
      .asFunction<int Function(Pointer<Void>, int, Pointer<Pointer<Void>>)>();
  final getTokenInformation = _advapi
      .lookup<
        NativeFunction<
          Int32 Function(
            Pointer<Void>,
            Int32,
            Pointer<Void>,
            Uint32,
            Pointer<Uint32>,
          )
        >
      >('GetTokenInformation')
      .asFunction<
        int Function(Pointer<Void>, int, Pointer<Void>, int, Pointer<Uint32>)
      >();
  final closeHandle = _kernel32
      .lookup<NativeFunction<Int32 Function(Pointer<Void>)>>('CloseHandle')
      .asFunction<int Function(Pointer<Void>)>();

  final token = calloc<Pointer<Void>>();
  try {
    // TOKEN_QUERY
    if (openProcessToken(getCurrentProcess(), 0x0008, token) == 0) {
      return false;
    }
    try {
      final elevation = calloc<Uint32>();
      try {
        // TokenElevation
        final ok = getTokenInformation(
          token.value,
          20,
          elevation.cast(),
          4,
          nullptr,
        );
        return ok != 0 && elevation.value != 0;
      } finally {
        calloc.free(elevation);
      }
    } finally {
      closeHandle(token.value);
    }
  } finally {
    calloc.free(token);
  }
}

/// 以管理员权限执行 bat 脚本：已提权时直接 `cmd /c`，否则弹 UAC（runas）。
///
/// 返回退出码；用户取消 UAC 返回 [errorCancelled]。
Future<int> _runElevated(String script) async {
  final bat = File(
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'clashy_svc_${pid}_${DateTime.now().millisecondsSinceEpoch}.bat',
  );
  await bat.writeAsString(script);
  try {
    if (_isElevated()) {
      return await Isolate.run(
        () => _shellExecuteRunas(bat.path, elevated: true),
      );
    }
    return await Isolate.run(() => _shellExecuteRunas(bat.path));
  } finally {
    try {
      await bat.delete();
    } catch (_) {}
  }
}

/// ShellExecuteExW(runas) 启动 `cmd /c <bat>` 并等待退出码。
///
/// 阻塞调用，应在工作 isolate 中运行（UAC 交互期间不卡 UI isolate）。
int _shellExecuteRunas(String batPath, {bool elevated = false}) {
  final shellExecuteEx = _shell32
      .lookup<NativeFunction<Int32 Function(Pointer<_ShellExecuteInfo>)>>(
        'ShellExecuteExW',
      )
      .asFunction<int Function(Pointer<_ShellExecuteInfo>)>();
  final getLastError = _kernel32
      .lookup<NativeFunction<Uint32 Function()>>('GetLastError')
      .asFunction<int Function()>();
  final waitForSingleObject = _kernel32
      .lookup<NativeFunction<Uint32 Function(Pointer<Void>, Uint32)>>(
        'WaitForSingleObject',
      )
      .asFunction<int Function(Pointer<Void>, int)>();
  final getExitCodeProcess = _kernel32
      .lookup<NativeFunction<Int32 Function(Pointer<Void>, Pointer<Uint32>)>>(
        'GetExitCodeProcess',
      )
      .asFunction<int Function(Pointer<Void>, Pointer<Uint32>)>();
  final closeHandle = _kernel32
      .lookup<NativeFunction<Int32 Function(Pointer<Void>)>>('CloseHandle')
      .asFunction<int Function(Pointer<Void>)>();

  final info = calloc<_ShellExecuteInfo>();
  final verb = elevated ? nullptr : 'runas'.toNativeUtf16();
  final file = 'cmd.exe'.toNativeUtf16();
  final params = '/c "${batPath.replaceAll('/', '\\')}"'.toNativeUtf16();
  try {
    info.ref.cbSize = sizeOf<_ShellExecuteInfo>();
    // SEE_MASK_NOCLOSEPROCESS：拿到子进程句柄以等待退出码
    info.ref.fMask = 0x00000040;
    info.ref.lpVerb = verb;
    info.ref.lpFile = file;
    info.ref.lpParameters = params;
    // SW_HIDE：静默执行服务管理脚本，不显示 cmd 窗口。
    info.ref.nShow = 0;

    if (shellExecuteEx(info) == 0) {
      final err = getLastError();
      // ERROR_CANCELLED：用户点了 UAC 弹窗的“否”
      return err == errorCancelled ? errorCancelled : (err == 0 ? 1 : err);
    }

    final hProcess = info.ref.hProcess;
    if (hProcess.address == 0) return 0;
    try {
      // INFINITE
      waitForSingleObject(hProcess, 0xFFFFFFFF);
      final code = calloc<Uint32>();
      try {
        if (getExitCodeProcess(hProcess, code) != 0) return code.value;
        return 1;
      } finally {
        calloc.free(code);
      }
    } finally {
      closeHandle(hProcess);
    }
  } finally {
    if (verb != nullptr) calloc.free(verb);
    calloc.free(file);
    calloc.free(params);
    calloc.free(info);
  }
}

final class _ShellExecuteInfo extends Struct {
  @Uint32()
  external int cbSize;
  @Uint32()
  external int fMask;
  external Pointer<Void> hwnd;
  external Pointer<Utf16> lpVerb;
  external Pointer<Utf16> lpFile;
  external Pointer<Utf16> lpParameters;
  external Pointer<Utf16> lpDirectory;
  @Int32()
  external int nShow;
  external Pointer<Void> hInstApp;
  external Pointer<Void> lpIDList;
  external Pointer<Utf16> lpClass;
  external Pointer<Void> hkeyClass;
  @Uint32()
  external int dwHotKey;
  external Pointer<Void> hIcon;
  external Pointer<Void> hProcess;
}
