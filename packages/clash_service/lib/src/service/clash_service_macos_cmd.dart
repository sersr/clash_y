import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class HelperInstaller {
  static const _serviceId = 'com.aote.clashy.helper';
  static const _plistPath =
      '/Library/LaunchDaemons/com.aote.clashy.helper.plist';
  static const _helperDst =
      '/Library/PrivilegedHelperTools/com.aote.clashy.helper';
  static const _helperClashlibDst =
      '/Library/PrivilegedHelperTools/com.aote.clashy.helper.clash';
  static const _helperWakeMonitorDst =
      '/Library/PrivilegedHelperTools/com.aote.clashy.helper.wake';
  static const _logFile = '/var/log/clashy-install.log';
  static const _serviceLogFile = '/var/log/clashy-service.log';
  static const _serviceErrorLogFile = '/var/log/clashy-service-error.log';

  /// bundle 内源文件相对路径（相对于 .app 根目录）
  static const _helperRel =
      'Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/'
      'packages/clash_service/bin/clashyService';
  static const _clashRel =
      'Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/'
      'packages/clash_service/lib/libclash.dylib';
  static const _wakeMonitorRel =
      'Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/'
      'packages/clash_service/lib/clash_wake_monitor.dylib';

  /// 当前 .app bundle 的绝对路径
  static String get _bundlePath {
    final exe = Platform.resolvedExecutable;
    final idx = exe.indexOf('/Contents/MacOS/');
    if (idx < 0) throw StateError('无法解析 App bundle 路径: $exe');
    return exe.substring(0, idx);
  }

  static String get _helperSrc => '$_bundlePath/$_helperRel';
  static String get _clashSrc => '$_bundlePath/$_clashRel';
  static String get _wakeMonitorSrc => '$_bundlePath/$_wakeMonitorRel';

  /// helper 是否已安装并运行
  static Future<bool> isInstalled() async {
    final r = await Process.run('launchctl', ['print', 'system/$_serviceId']);
    return r.exitCode == 0;
  }

  /// daemon 是否正在运行
  static Future<bool> isRunning() async {
    final r = await Process.run('launchctl', ['print', 'system/$_serviceId']);
    if (r.exitCode != 0) return false;
    return (r.stdout as String).contains('state = running');
  }

  static Future<bool> hasOtherVpnConnection({
    bool checkTunnelRoutes = true,
  }) async {
    final connections = await Process.run('/usr/sbin/scutil', ['--nc', 'list']);
    if (connections.exitCode != 0) {
      throw ProcessException(
        '/usr/sbin/scutil',
        const ['--nc', 'list'],
        '${connections.stderr}',
        connections.exitCode,
      );
    }
    if (RegExp(
      r'\(\s*Connected\s*\)',
      caseSensitive: false,
    ).hasMatch(connections.stdout as String)) {
      return true;
    }
    if (!checkTunnelRoutes) return false;

    final routes = await Process.run('/usr/sbin/netstat', [
      '-rn',
      '-f',
      'inet',
    ]);
    if (routes.exitCode != 0) {
      throw ProcessException(
        '/usr/sbin/netstat',
        const ['-rn', '-f', 'inet'],
        '${routes.stderr}',
        routes.exitCode,
      );
    }

    return (routes.stdout as String).split('\n').any((line) {
      final fields = line.trim().split(RegExp(r'\s+'));
      return fields.length >= 4 &&
          fields.any((field) => RegExp(r'^utun\d+$').hasMatch(field));
    });
  }

  /// LaunchDaemon 当前配置是否与 app bundle 路径生成的 plist 一致。
  static Future<bool> _isUpToDate(String expectedPlist) async {
    try {
      final plist = File(_plistPath);
      if (!await plist.exists()) return false;
      final installedPlist = (await plist.readAsString()).replaceAll(
        RegExp(
          r'^[ \t]*<!-- Bundle asset SHA-256: (?:[0-9a-f]{64})(?: [0-9a-f]{64})* -->\r?\n',
          multiLine: true,
        ),
        '',
      );
      return installedPlist == expectedPlist;
    } on FileSystemException {
      return false;
    }
  }

  static Future<void> _validateBundleAssets() async {
    final bundlePath = p.normalize(p.absolute(_bundlePath));
    if (!p.basename(bundlePath).endsWith('.app')) {
      throw StateError(
        'macOS service requires an app bundle in a system-protected location',
      );
    }

    final assets = <(String, FileSystemEntityType)>[
      (_helperSrc, FileSystemEntityType.file),
      (_clashSrc, FileSystemEntityType.file),
      (_wakeMonitorSrc, FileSystemEntityType.file),
    ];
    final checkedModes = <String, int>{};
    for (final (assetPath, expectedType) in assets) {
      final path = p.normalize(p.absolute(assetPath));
      if (!p.isWithin(bundlePath, path)) {
        throw StateError(
          'macOS service asset is outside the app bundle: $path',
        );
      }

      var current = '/';
      for (final component in p.relative(path, from: '/').split('/')) {
        current = p.join(current, component);
        final type = await FileSystemEntity.type(current, followLinks: false);
        if (type == FileSystemEntityType.link ||
            type == FileSystemEntityType.notFound) {
          throw StateError(
            'macOS service path is missing or contains a symlink: $current',
          );
        }
        final mode = checkedModes[current] ?? await _readMode(current);
        checkedModes[current] = mode;
        if ((current == bundlePath || p.isWithin(bundlePath, current)) &&
            (mode & 0x12) != 0) {
          throw StateError(
            'macOS service path must not be writable by other users: '
            '$current',
          );
        }
        if (assetPath == _helperSrc && current == path && (mode & 0x40) == 0) {
          throw StateError('macOS service helper is not executable: $path');
        }
      }

      if (await FileSystemEntity.type(path, followLinks: false) !=
          expectedType) {
        throw StateError('macOS service asset is missing: $path');
      }
    }
  }

  static Future<int> _readMode(String path) async {
    final result = await Process.run('/usr/bin/stat', ['-f', '%Lp', path]);
    if (result.exitCode != 0) {
      throw ProcessException(
        '/usr/bin/stat',
        ['-f', '%Lp', path],
        '${result.stderr}',
        result.exitCode,
      );
    }
    final permissions = (result.stdout as String).trim();
    if (!RegExp(r'^[0-7]{3,4}$').hasMatch(permissions)) {
      throw FormatException(
        'Unexpected stat output for $path: ${result.stdout}',
      );
    }
    return int.parse(permissions, radix: 8);
  }

  /// 安装 helper（弹系统密码框）。
  ///
  /// LaunchDaemon 直接运行 app bundle 中的 helper。配置只依赖 bundle 路径，
  /// 避免 clean 后重编译的二进制哈希变化导致重复请求管理员授权。
  static Future<void> install() async {
    await _validateBundleAssets();
    final plist = await _launchDaemonPlist();
    if (await _isUpToDate(plist)) {
      if (!await isRunning()) {
        await _runPrivileged(_buildStartScript());
      }
    } else {
      await _runPrivileged(_buildInstallScript(plist));
    }
    await _waitUntilRunning();
  }

  static Future<void> _waitUntilRunning() async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      if (await isRunning()) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }

    throw StateError(
      'macOS helper did not enter the running state. '
      'See $_serviceLogFile and $_serviceErrorLogFile.',
    );
  }

  /// 停止 helper（弹系统密码框），仅停止 daemon，保留已安装文件
  static Future<void> stop() async {
    await _runPrivileged(_buildStopScript());
  }

  /// 卸载 helper（弹系统密码框）
  static Future<void> uninstall() async {
    await _runPrivileged(_buildUninstallScript());
  }

  /// 读取安装日志
  static Future<String> readLog() async {
    final f = File(_logFile);
    if (!await f.exists()) return '(暂无日志)';
    return f.readAsString();
  }

  // ==================== 脚本内容 ====================

  static String _buildInstallScript(String plistContents) {
    final plistBase64 = base64.encode(utf8.encode(plistContents));
    return '''
#!/bin/bash

log() { echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$*" | tee -a "$_logFile"; }

log "========== install-helper 开始 =========="

if launchctl print "system/$_serviceId" >/dev/null 2>&1; then
    log "停止并卸载旧实例..."
    if ! launchctl bootout "system/$_serviceId"; then
        log "❌ bootout 旧实例失败，取消覆盖安装"
        exit 1
    fi
    sleep 1
fi

printf '%s' '$plistBase64' | /usr/bin/base64 -D > "$_plistPath"
if [ \$? -ne 0 ]; then
    log "❌ 生成 LaunchDaemon plist 失败"
    exit 1
fi

if ! plutil -lint "$_plistPath" >/dev/null; then
    log "❌ LaunchDaemon plist 无效"
    exit 1
fi

chown root:wheel "$_plistPath"
chmod 644 "$_plistPath"
log "plist 已写入 $_plistPath"

rm -f "$_helperDst" "$_helperClashlibDst" "$_helperWakeMonitorDst"

launchctl bootstrap system "$_plistPath" || log "bootstrap 失败，退出码 \$?"
launchctl enable "system/$_serviceId" 2>/dev/null || true
launchctl kickstart -kp "system/$_serviceId" 2>/dev/null || log "kickstart 失败"

if launchctl print "system/$_serviceId" >/dev/null 2>&1; then
    log "✅ 服务已加载"
else
    log "❌ 服务未加载"
    exit 1
fi

i=0
while [ \$i -lt 30 ]; do
    if launchctl print "system/$_serviceId" 2>/dev/null | grep -q "state = running"; then
        log "✅ 服务已进入运行状态"
        exit 0
    fi
    sleep 1
    i=\$((i + 1))
done

log "❌ 服务未能进入运行状态"
launchctl print "system/$_serviceId" 2>&1 | tee -a "$_logFile"
tail -50 "$_serviceErrorLogFile" "$_serviceLogFile" 2>/dev/null | tee -a "$_logFile"
exit 1
''';
  }

  static Future<String> _launchDaemonPlist() async {
    final arguments = [
      _helperSrc,
      '--clash-library',
      _clashSrc,
      '--wake-monitor-library',
      _wakeMonitorSrc,
    ];
    final programArguments = arguments
        .map((argument) => '<string>${_escapeXml(argument)}</string>')
        .join();
    return '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$_serviceId</string>
    <key>ProgramArguments</key>
    <array>$programArguments</array>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$_serviceLogFile</string>
    <key>StandardErrorPath</key>
    <string>$_serviceErrorLogFile</string>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
</dict>
</plist>
''';
  }

  static String _escapeXml(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  /// 文件已一致时仅启动服务，不复制
  static String _buildStartScript() {
    return '''
#!/bin/bash

log() { echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$*" | tee -a "$_logFile"; }

log "========== start-helper 开始 =========="

if [ ! -f "$_plistPath" ]; then
    log "❌ 找不到 plist: $_plistPath"
    exit 1
fi

if launchctl print "system/$_serviceId" 2>/dev/null | grep -q "state = running"; then
    log "✅ 服务已在运行"
    exit 0
fi

if launchctl print "system/$_serviceId" >/dev/null 2>&1; then
    launchctl kickstart "system/$_serviceId" 2>/dev/null || log "kickstart 失败"
else
    launchctl bootstrap system "$_plistPath" || log "bootstrap 失败，退出码 \$?"
fi
launchctl enable "system/$_serviceId" 2>/dev/null || true

i=0
while [ \$i -lt 30 ]; do
    if launchctl print "system/$_serviceId" 2>/dev/null | grep -q "state = running"; then
        log "✅ 服务已进入运行状态"
        exit 0
    fi
    sleep 1
    i=\$((i + 1))
done

log "❌ 服务未能进入运行状态"
launchctl print "system/$_serviceId" 2>&1 | tee -a "$_logFile"
tail -50 "$_serviceErrorLogFile" "$_serviceLogFile" 2>/dev/null | tee -a "$_logFile"
exit 1
''';
  }

  /// 仅停止 daemon，保留 plist 与 app bundle 资源
  static String _buildStopScript() {
    return '''
#!/bin/bash

log() { echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$*" | tee -a "$_logFile"; }

log "========== stop-helper 开始 =========="

if launchctl print "system/$_serviceId" >/dev/null 2>&1; then
    if launchctl bootout "system/$_serviceId" 2>/dev/null; then
        log "✅ 服务已停止"
    else
        log "❌ bootout 失败"
        exit 1
    fi
else
    log "服务未在运行"
fi
exit 0
''';
  }

  static String _buildUninstallScript() {
    return '''
#!/bin/bash

if launchctl print "system/$_serviceId" >/dev/null 2>&1; then
    launchctl bootout "system/$_serviceId" 2>/dev/null || true
fi

rm -f "$_plistPath" "$_helperDst" "$_helperClashlibDst" "$_helperWakeMonitorDst"
echo "已卸载 $_serviceId"
''';
  }

  // ==================== 提权执行 ====================

  static Future<void> _runPrivileged(String script) async {
    // base64 编码，彻底避开引号/换行转义问题
    final b64 = base64.encode(utf8.encode(script));

    // base64 字符集是 A-Za-z0-9+/=，没有单引号，可安全放进 shell 单引号
    final shellCmd = "echo '$b64' | base64 -d | bash";

    // AppleScript 用双引号，内部 shell 命令已经用单引号隔离，无冲突
    final appleScript =
        'do shell script "$shellCmd" with administrator privileges';

    final r = await Process.run('osascript', ['-e', appleScript]);
    print('${r.stdout}\n${r.stderr}\ncode: ${r.exitCode}');
    if (r.exitCode != 0) {
      final err = (r.stderr as String).trim();
      // 用户点了取消
      if (err.contains('User canceled') || err.contains('-128')) {
        throw const HelperInstallCanceled();
      }
      throw Exception('提权执行失败: $err ${r.stdout}');
    }
  }
}

class HelperInstallCanceled implements Exception {
  const HelperInstallCanceled();
  @override
  String toString() => '用户取消了安装';
}
