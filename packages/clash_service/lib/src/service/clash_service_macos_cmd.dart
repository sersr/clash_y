import 'dart:convert';
import 'dart:io';

class HelperInstaller {
  static const _serviceId = 'com.aote.clashy.helper';
  static const _plistPath =
      '/Library/LaunchDaemons/com.aote.clashy.helper.plist';
  static const _helperDst =
      '/Library/PrivilegedHelperTools/com.aote.clashy.helper';
  static const _helperClashlibDst =
      '/Library/PrivilegedHelperTools/com.aote.clashy.helper.clash';
  static const _logFile = '/var/log/clashy-install.log';

  /// bundle 内源文件相对路径（相对于 .app 根目录）
  static const _helperRel =
      'Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/'
      'packages/clash_service/bin/clashyService';
  static const _clashRel =
      'Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/'
      'packages/clash_service/lib/libclash.dylib';

  /// 当前 .app bundle 的绝对路径
  static String get _bundlePath {
    final exe = Platform.resolvedExecutable;
    final idx = exe.indexOf('/Contents/MacOS/');
    if (idx < 0) throw StateError('无法解析 App bundle 路径: $exe');
    return exe.substring(0, idx);
  }

  static String get _helperSrc => '$_bundlePath/$_helperRel';
  static String get _clashSrc => '$_bundlePath/$_clashRel';

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

  /// 已安装文件是否与 bundle 内文件完全一致（且 plist 存在）
  static Future<bool> _isUpToDate() async {
    try {
      final helperSrc = File(_helperSrc);
      final helperDst = File(_helperDst);
      final clashSrc = File(_clashSrc);
      final clashDst = File(_helperClashlibDst);

      if (!await helperSrc.exists() || !await helperDst.exists()) return false;
      if (!await clashSrc.exists() || !await clashDst.exists()) return false;
      if (!await File(_plistPath).exists()) return false;

      return await _identical(helperSrc, helperDst) &&
          await _identical(clashSrc, clashDst);
    } on FileSystemException {
      return false;
    }
  }

  static Future<bool> _identical(File a, File b) async {
    if (await a.length() != await b.length()) return false;
    final r = await Process.run('cmp', ['-s', a.path, b.path]);
    return r.exitCode == 0;
  }

  /// 安装 helper（弹系统密码框）。
  ///
  /// 已安装文件与 bundle 内文件一致时跳过复制：服务在运行则直接返回，
  /// 未运行则仅启动服务。
  static Future<void> install() async {
    if (await _isUpToDate()) {
      if (await isRunning()) return;
      await _runPrivileged(_buildStartScript());
      return;
    }
    await _runPrivileged(_buildInstallScript());
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

  static String _buildInstallScript() {
    return '''
#!/bin/bash

log() { echo "[\$(date '+%Y-%m-%d %H:%M:%S')] \$*" | tee -a "$_logFile"; }

log "========== install-helper 开始 =========="

if [ ! -f "$_helperSrc" ]; then
    log "❌ 找不到源二进制: $_helperSrc"
    exit 1
fi

mkdir -p /Library/PrivilegedHelperTools
cp -f "$_helperSrc" "$_helperDst"
chown root:wheel "$_helperDst"
chmod 755 "$_helperDst"
xattr -cr "$_helperDst" 2>/dev/null || true
log "helper 已安装到 $_helperDst"

if [ ! -f "$_clashSrc" ]; then
    log "❌ 找不到 libclash.dylib: $_clashSrc"
    exit 1
fi

cp -f "$_clashSrc" "$_helperClashlibDst"
chown root:wheel "$_helperClashlibDst"
chmod 755 "$_helperClashlibDst"
xattr -cr "$_helperClashlibDst" 2>/dev/null || true
log "libclash.dylib 已安装到 $_helperClashlibDst"

cat > "$_plistPath" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$_serviceId</string>
    <key>Program</key>
    <string>$_helperDst</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
</dict>
</plist>
PLIST

chown root:wheel "$_plistPath"
chmod 644 "$_plistPath"
log "plist 已写入 $_plistPath"

if launchctl print "system/$_serviceId" >/dev/null 2>&1; then
    log "卸载旧实例..."
    launchctl bootout "system/$_serviceId" 2>/dev/null || true
    sleep 1
fi

launchctl bootstrap system "$_plistPath" || log "bootstrap 失败，退出码 \$?"
launchctl enable "system/$_serviceId" 2>/dev/null || true
launchctl kickstart -kp "system/$_serviceId" 2>/dev/null || log "kickstart 失败"

if launchctl print "system/$_serviceId" >/dev/null 2>&1; then
    log "✅ 服务已加载"
    exit 0
else
    log "❌ 服务未加载"
    exit 1
fi
''';
  }

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

if launchctl print "system/$_serviceId" >/dev/null 2>&1; then
    log "✅ 服务已启动"
    exit 0
else
    log "❌ 服务未启动"
    exit 1
fi
''';
  }

  /// 仅停止 daemon，保留 plist 与已安装文件
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

rm -f "$_plistPath" "$_helperDst" "$_helperClashlibDst"
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
