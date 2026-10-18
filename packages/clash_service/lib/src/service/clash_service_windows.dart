import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

const windowService = 'clashy_service';

const _description = 'Clash VPN';

/// 安装服务（未提权时弹 UAC 密码框，与 Linux pkexec 对等）。
///
/// 用 `sc create/config` 写入服务配置，行为对应其他平台的 install：
/// - 开机自启（start= auto + DelayedAutostart，与原实现一致）
/// - 故障自动重启 5 次、间隔 5s、60s 内计数（对应 systemd 的
///   `Restart=on-failure` / `RestartSec=5` / `StartLimitBurst=5`）
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
  final code = await _runElevated('${_installScript()}sc start $windowService\n');
  if (code == errorCancelled) return false;
  for (var i = 0; i < 50 && !isServiceRunning(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  return isServiceRunning();
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
/// 并清理旧 DLL 实现残留的 EventLog 注册。
/// 返回服务是否已不存在；用户取消 UAC 返回 false。
Future<bool> uninstallService() async {
  if (!_serviceExists()) return true;
  const script = '''
sc stop $windowService >nul 2>&1
for /l %%i in (1,1,30) do (
  sc query $windowService >nul 2>&1 || goto :del
  sc query $windowService | findstr /c:"STOPPED" >nul && goto :del
  timeout /t 1 /nobreak >nul
)
:del
sc delete $windowService >nul 2>&1
reg delete "HKLM\\SYSTEM\\CurrentControlSet\\Services\\EventLog\\Application\\$windowService" /f >nul 2>&1
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

/// install 脚本（不含 start），行为见 [installService]。
String _installScript() {
  final raw = Platform.resolvedExecutable;
  // 含空格时 binPath 的值本身需带引号，否则 SCM 拆分导致启动失败
  final binPath = raw.contains(' ') ? '"\\"$raw\\""' : raw;
  return 'sc ${_serviceExists() ? 'config' : 'create'} $windowService '
          'binPath= $binPath start= auto\n'
      'sc description $windowService "$_description"\n'
      'sc failure $windowService reset= 60 '
      'actions= restart/5000/restart/5000/restart/5000/restart/5000/restart/5000\n'
      'reg add "HKLM\\SYSTEM\\CurrentControlSet\\Services\\$windowService" '
      '/v DelayedAutostart /t REG_DWORD /d 1 /f\n';
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

bool? _elevatedCache;
bool _isElevated() => _elevatedCache ??= _queryElevated();

bool _queryElevated() {
  final getCurrentProcess = _kernel32
      .lookup<NativeFunction<Pointer<Void> Function()>>('GetCurrentProcess')
      .asFunction<Pointer<Void> Function()>();
  final openProcessToken = _advapi
      .lookup<
        NativeFunction<Int32 Function(Pointer<Void>, Uint32, Pointer<Pointer<Void>>)>
      >('OpenProcessToken')
      .asFunction<int Function(Pointer<Void>, int, Pointer<Pointer<Void>>)>();
  final getTokenInformation = _advapi
      .lookup<
        NativeFunction<
          Int32 Function(Pointer<Void>, Int32, Pointer<Void>, Uint32, Pointer<Uint32>)
        >
      >('GetTokenInformation')
      .asFunction<int Function(Pointer<Void>, int, Pointer<Void>, int, Pointer<Uint32>)>();
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
        final ok = getTokenInformation(token.value, 20, elevation.cast(), 4, nullptr);
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
      final r = await Process.run('cmd', ['/c', bat.path]);
      return r.exitCode;
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
int _shellExecuteRunas(String batPath) {
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
  final verb = 'runas'.toNativeUtf16();
  final file = 'cmd.exe'.toNativeUtf16();
  final params = '/c "${batPath.replaceAll('/', '\\')}"'.toNativeUtf16();
  try {
    info.ref.cbSize = sizeOf<_ShellExecuteInfo>();
    // SEE_MASK_NOCLOSEPROCESS：拿到子进程句柄以等待退出码
    info.ref.fMask = 0x00000040;
    info.ref.lpVerb = verb;
    info.ref.lpFile = file;
    info.ref.lpParameters = params;
    // SW_SHOWNORMAL
    info.ref.nShow = 1;

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
    calloc.free(verb);
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

// ==================== SCM 握手（纯 FFI，无外部 DLL） ====================
//
// 线程模型（三方协作）：
// - 本 isolate（root，A）保持事件循环运转：ServiceMain 经
//   NativeCallable.listener 从 SCM 新建线程投递回 A 执行，负责注册控制
//   处理器并上报 SERVICE_RUNNING（文档允许 ServiceMain 线程提前退出）。
// - StartServiceCtrlDispatcher 阻塞至服务 STOPPED，放在独立 isolate B 中；
//   控制请求在派发线程（即 B 的 mutator 线程）上分发，因此控制处理器用
//   isolateLocal 在 B 内创建，可同步重入执行并返回 DWORD
//   （同 qsort 比较器模式，已实测验证）。
// - 控制处理器只操作堆上的 _HandlerCtx；收到 STOP 后由 A 的轮询任务补报
//   SERVICE_STOPPED，令 B 的派发调用返回，完成整个停止流程。

final _advapi = DynamicLibrary.open('advapi32.dll');

typedef _ServiceStatusHandle = IntPtr;
typedef _SetStatusNative = Int32 Function(
  _ServiceStatusHandle,
  Pointer<_ServiceStatus>,
);
typedef _SetStatusDart = int Function(int, Pointer<_ServiceStatus>);

typedef _RegisterHandlerNative = _ServiceStatusHandle Function(
  Pointer<Utf16>,
  Pointer<NativeFunction<_HandlerNative>>,
  Pointer<Void>,
);
typedef _RegisterHandlerDart = int Function(
  Pointer<Utf16>,
  Pointer<NativeFunction<_HandlerNative>>,
  Pointer<Void>,
);

typedef _DispatcherNative = Int32 Function(Pointer<_ServiceTableEntry>);
typedef _DispatcherDart = int Function(Pointer<_ServiceTableEntry>);

typedef _ServiceMainNative = Void Function(
  Uint32,
  Pointer<Pointer<Utf16>>,
);

typedef _HandlerNative = Uint32 Function(
  Uint32,
  Uint32,
  Pointer<Void>,
  Pointer<Void>,
);

final class _ServiceStatus extends Struct {
  @Uint32()
  external int dwServiceType;
  @Uint32()
  external int dwCurrentState;
  @Uint32()
  external int dwControlsAccepted;
  @Uint32()
  external int dwWin32ExitCode;
  @Uint32()
  external int dwServiceSpecificExitCode;
  @Uint32()
  external int dwCheckPoint;
  @Uint32()
  external int dwWaitHint;
}

final class _HandlerCtx extends Struct {
  external Pointer<NativeFunction<_SetStatusNative>> setStatus;
  @IntPtr()
  external int statusHandle;
  external Pointer<_ServiceStatus> status;
  @Uint32()
  external int stopRequested;
}

final class _ServiceTableEntry extends Struct {
  external Pointer<Utf16> lpServiceName;
  external Pointer<NativeFunction<_ServiceMainNative>> lpServiceProc;
}

class _DispatcherArgs {
  _DispatcherArgs(this.tableAddr, this.port);
  final int tableAddr;
  final SendPort port;
}

final _SetStatusDart _setServiceStatus = _advapi
    .lookup<NativeFunction<_SetStatusNative>>('SetServiceStatusW')
    .asFunction<_SetStatusDart>();
final _RegisterHandlerDart _registerCtrlHandlerEx = _advapi
    .lookup<NativeFunction<_RegisterHandlerNative>>(
      'RegisterServiceCtrlHandlerExW',
    )
    .asFunction<_RegisterHandlerDart>();

// 以下状态仅在本 isolate（A）中访问。
Pointer<_HandlerCtx>? _serviceCtx;
Pointer<Utf16>? _serviceNamePtr;
int? _handlerAddr;

/// 连接服务控制管理器，阻塞直至服务停止。
///
/// 仅在由 SCM 启动（`sc start` 或开机自启）的进程中有效；控制台直接运行
/// 时 StartServiceCtrlDispatcher 立即失败并返回（与原 DLL 行为一致）。
Future<void> connectWindowScm() async {
  final ctx = calloc<_HandlerCtx>();
  ctx.ref.status = calloc<_ServiceStatus>();
  ctx.ref.setStatus =
      _advapi.lookup<NativeFunction<_SetStatusNative>>('SetServiceStatusW');

  final serviceMain = NativeCallable<_ServiceMainNative>.listener(_serviceMain);
  final name = windowService.toNativeUtf16();

  final table = calloc<_ServiceTableEntry>(2);
  table[0].lpServiceName = name;
  table[0].lpServiceProc = serviceMain.nativeFunction;

  _serviceCtx = ctx;
  _serviceNamePtr = name;
  _handlerAddr = null;

  final done = Completer<void>();
  final port = ReceivePort();
  port.listen((msg) {
    if (msg is int) {
      // B 已创建控制处理器，ServiceMain 注册时使用
      _handlerAddr = msg;
    } else if (!done.isCompleted) {
      done.complete();
    }
  });

  await Isolate.spawn(
    _dispatcherEntry,
    _DispatcherArgs(table.address, port.sendPort),
  );

  final timer = Timer.periodic(const Duration(milliseconds: 100), (t) {
    if (ctx.ref.stopRequested == 0) return;
    final st = ctx.ref.status;
    st.ref.dwCurrentState = 4; // SERVICE_STOPPED
    st.ref.dwCheckPoint = 0;
    st.ref.dwWaitHint = 0;
    if (ctx.ref.statusHandle != 0) {
      _setServiceStatus(ctx.ref.statusHandle, st);
    }
    t.cancel();
    if (!done.isCompleted) done.complete();
  });

  await done.future;
  timer.cancel();
  port.close();
}

/// 独立 isolate B：创建控制处理器（须与派发调用同线程），
/// 阻塞在派发调用上，返回（服务已停止或注册失败）时通知 A。
void _dispatcherEntry(_DispatcherArgs args) {
  final handler = NativeCallable<_HandlerNative>.isolateLocal(
    _serviceHandler,
    exceptionalReturn: 0,
  );
  args.port.send(handler.nativeFunction.address);

  final dispatcher = DynamicLibrary.open('advapi32.dll')
      .lookup<NativeFunction<_DispatcherNative>>(
        'StartServiceCtrlDispatcherW',
      )
      .asFunction<_DispatcherDart>();
  dispatcher(Pointer<_ServiceTableEntry>.fromAddress(args.tableAddr));

  handler.close();
  args.port.send('done');
}

/// ServiceMain：经 listener 投递回 A 执行，注册控制处理器并上报 RUNNING。
void _serviceMain(int argc, Pointer<Pointer<Utf16>> argv) {
  _tryRegisterAndRun(0);
}

void _tryRegisterAndRun(int attempt) {
  final ctx = _serviceCtx;
  final name = _serviceNamePtr;
  final handlerAddr = _handlerAddr;
  if (ctx == null || name == null) return;
  if (handlerAddr == null) {
    // 防御：handler 地址由 B 经消息送达，理论上先于本回调入队；仍做重试
    if (attempt >= 100) return;
    Timer(const Duration(milliseconds: 100), () {
      _tryRegisterAndRun(attempt + 1);
    });
    return;
  }

  final handle = _registerCtrlHandlerEx(
    name,
    Pointer<NativeFunction<_HandlerNative>>.fromAddress(handlerAddr),
    ctx.cast<Void>(),
  );
  ctx.ref.statusHandle = handle;

  final st = ctx.ref.status;
  st.ref.dwServiceType = 0x10; // SERVICE_WIN32_OWN_PROCESS
  st.ref.dwCurrentState = 4; // SERVICE_RUNNING
  st.ref.dwControlsAccepted = 0x3; // ACCEPT_STOP | ACCEPT_SHUTDOWN
  st.ref.dwWin32ExitCode = 0;
  st.ref.dwCheckPoint = 0;
  st.ref.dwWaitHint = 0;
  if (handle != 0) _setServiceStatus(handle, st);
}

/// 控制处理器：在 B 的派发线程同步重入执行，禁止访问本 isolate 静态字段，
/// 全部状态经堆上 context 传递。
int _serviceHandler(
  int control,
  int eventType,
  Pointer<Void> eventData,
  Pointer<Void> context,
) {
  try {
    final ctx = context.cast<_HandlerCtx>();
    final setStatus = ctx.ref.setStatus.asFunction<_SetStatusDart>();
    if (control == 1 /* SERVICE_CONTROL_STOP */ ||
        control == 6 /* SERVICE_CONTROL_SHUTDOWN */) {
      final st = ctx.ref.status;
      st.ref.dwCurrentState = 3; // SERVICE_STOP_PENDING
      st.ref.dwCheckPoint = 1;
      st.ref.dwWaitHint = 30000;
      if (ctx.ref.statusHandle != 0) {
        setStatus(ctx.ref.statusHandle, st);
      }
      // 由 A 的轮询任务补报 SERVICE_STOPPED
      ctx.ref.stopRequested = 1;
    } else if (control == 4 /* SERVICE_CONTROL_INTERROGATE */) {
      if (ctx.ref.statusHandle != 0) {
        setStatus(ctx.ref.statusHandle, ctx.ref.status);
      }
    }
    return 0;
  } catch (_) {
    return 0;
  }
}
