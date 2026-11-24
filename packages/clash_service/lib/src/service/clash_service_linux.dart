import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:server/tray_asset.dart';

/// systemd unit 文件路径。
const systemdUnitPath = '/etc/systemd/system/clashy-service.service';

/// clashyService 可执行文件路径。
///
/// 应用进程从 Flutter 数据资产目录启动后台服务；直接运行 clashyService
/// （例如开发调试）时复用当前可执行文件。
String get clashServiceExecutablePath {
  final executable = Platform.resolvedExecutable;
  if (p.basename(executable) == clashServiceExecutableName) {
    return executable;
  }
  return p.join(
    p.dirname(executable),
    'data',
    'flutter_assets',
    clashServiceAssetPackagePath,
    'bin',
    clashServiceExecutableName,
  );
}

/// systemd unit 是否已安装。查询无需 root。
Future<bool> isSystemdServiceInstalled() => File(systemdUnitPath).exists();

/// 安装或重启 systemd 服务（写入 unit + enable + start/restart）。
///
/// 当前进程没有 root 权限时，通过 pkexec 弹出 polkit 密码框提权：
/// 写入 unit 文件 -> daemon-reload -> enable -> start，一次授权完成。
///
/// 返回退出码，0 表示成功。
Future<int> installSystemdService({bool forceRestart = false}) async {
  final exePath = clashServiceExecutablePath;
  if (!File(exePath).existsSync()) {
    throw StateError('Bundled Linux clashyService is missing: $exePath');
  }
  // systemd ExecStart 路径含空格时需要引号
  final exec = exePath.contains(' ') ? '"$exePath"' : exePath;

  final script =
      '''
set -e
mkdir -p /etc/systemd/system
cat > $systemdUnitPath <<'EOF'
[Unit]
Description=Clash VPN
After=network-online.target nftables.service iptables.service
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
Type=simple
ExecStart=$exec
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable clashy-service.service
systemctl ${forceRestart ? 'restart' : 'start'} clashy-service.service
''';

  return _runAsRoot(script);
}

/// 停止 systemd 服务（保留 unit 文件，下次开机仍会自动启动）。
///
/// 服务未运行时直接返回，不弹密码框。
Future<int> stopSystemdService() async {
  if (!await isSystemdServiceRunning()) return 0;
  return _runAsRoot('systemctl stop clashy-service.service');
}

/// 卸载 systemd 服务（disable + 删除 unit 文件）。
///
/// unit 文件不存在时直接返回，不弹密码框。
Future<int> uninstallSystemdService() async {
  if (!await File(systemdUnitPath).exists()) {
    return 0;
  }

  final script =
      '''
systemctl disable --now clashy-service.service 2>/dev/null || true
rm -f $systemdUnitPath
systemctl daemon-reload
''';

  return _runAsRoot(script);
}

/// 服务是否处于 active 状态（查询无需 root）。
Future<bool> isSystemdServiceRunning() async {
  final r = await Process.run('systemctl', [
    'is-active',
    '--quiet',
    'clashy-service.service',
  ]);
  return r.exitCode == 0;
}

/// 以 root 执行脚本。
///
/// base64 编码后经 pkexec 执行，避免引号/换行转义问题。
/// 用户取消授权时 pkexec 退出码为 126。
Future<int> _runAsRoot(String script) async {
  final b64 = base64.encode(utf8.encode(script));
  final result = await Process.run('pkexec', [
    'sh',
    '-c',
    "echo '$b64' | base64 -d | sh",
  ]);
  final err = (result.stderr as String).trim();
  if (result.exitCode != 0 && err.isNotEmpty) {
    print(err);
  }
  return result.exitCode;
}
