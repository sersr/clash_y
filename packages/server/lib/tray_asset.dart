const clashTrayExecutableName = 'clashyTray';
const clashWindowsServiceExecutableName = 'clashyservice.exe';
const clashServiceAssetPackagePath = 'packages/clash_service';
const clashTunHelperExecutableName = 'clashyTunHelper';
const clashTunHelperWindowsExecutableName = 'clashyTunHelper.exe';

/// TUN helper 在三个桌面平台上的二进制文件名。
String clashTunHelperFileName({required bool windows}) => windows
    ? clashTunHelperWindowsExecutableName
    : clashTunHelperExecutableName;

/// TUN helper 的 IPC 端点，与 Go 侧 `tunbroker` 常量保持一致。
const clashTunHelperSocketPath = '/var/run/clashy-tun-helper.sock';
const clashTunHelperPipePath = r'\\.\pipe\clashy\tun_helper.pipe';

/// 原生辅助二进制（tray、TUN helper）的稳定输出目录，相对 cmd 包根目录。
///
/// 不放在 `dart build cli` 的 bundle 输出目录里，避免每次构建被整体删除。
const clashNativeBinDirRelativePath = 'build/native/bin';
