const clashTrayExecutableName = 'clashyTray';
const clashTunHelperExecutableName = 'clashyTunHelper';

/// 原生辅助二进制（tray、TUN helper）的稳定输出目录，相对 cmd 包根目录。
///
/// 不放在 `dart build cli` 的 bundle 输出目录里，避免每次构建被整体删除。
const clashNativeBinDirRelativePath = 'build/native/bin';
