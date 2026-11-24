/// macOS 托盘的可执行文件名。
const clashTrayExecutableName = 'clashyTray';

/// 桌面服务端在 macOS/Linux 上的可执行文件名。
const clashServiceExecutableName = 'clashyService';

/// 桌面服务端在 Windows 上的可执行文件名（应用与 TUN helper 的白名单共用）。
const clashWindowsServiceExecutableName = 'clashyservice.exe';

/// 随包原生二进制在 Flutter 资源里的包目录。
const clashServiceAssetPackagePath = 'packages/clash_service';

/// 特权 TUN helper 在 macOS/Linux 上的可执行文件名。
const clashTunHelperExecutableName = 'clashyTunHelper';

/// 特权 TUN helper 在 Windows 上的可执行文件名。
const clashTunHelperWindowsExecutableName = 'clashyTunHelper.exe';

/// TUN helper 在各桌面平台上的二进制文件名。
String clashTunHelperFileName({required bool windows}) => windows
    ? clashTunHelperWindowsExecutableName
    : clashTunHelperExecutableName;

/// 原生二进制（服务端、TUN helper、托盘）的稳定输出目录，相对
/// `packages/clash_service` 包根目录。
///
/// 产物先落在这里，再由该包的构建钩子作为 `bin/*` 数据资产交付；不放进每次
/// 构建都会被整体删除的临时输出目录。
const clashNativeBinDirRelativePath = 'build/bin';
