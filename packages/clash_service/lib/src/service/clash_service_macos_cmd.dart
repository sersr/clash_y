import 'dart:convert';
import 'dart:io';

class HelperInstaller {
  static const _serviceId = 'com.aote.clashy.helper';
  static const _plistPath = '/Library/LaunchDaemons/com.aote.clashy.helper.plist';
  static const _helperDst = '/Library/PrivilegedHelperTools/com.aote.clashy.helper';
  static const _helperClashlibDst = '/Library/PrivilegedHelperTools/com.aote.clashy.helper.clash';
  static const _logFile = '/var/log/clashy-install.log';

  /// 当前 .app bundle 的绝对路径
  static String get _bundlePath {
    final exe = Platform.resolvedExecutable;
    final idx = exe.indexOf('/Contents/MacOS/');
    if (idx < 0) throw StateError('无法解析 App bundle 路径: $exe');
    return exe.substring(0, idx);
  }

  /// helper 是否已安装并运行
  static Future<bool> isInstalled() async {
    final r = await Process.run(
      'launchctl',
      ['print', 'system/$_serviceId'],
    );
    return r.exitCode == 0;
  }

  /// 安装 helper（弹系统密码框）
  static Future<void> install() async {
    await _runPrivileged(_buildInstallScript());
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
    final bundle = _bundlePath;
    return r'''
#!/bin/bash
set -u

BUNDLE_PATH="''' + bundle + r'''"
PLIST_PATH="''' + _plistPath + r'''"
SERVICE_ID="''' + _serviceId + r'''"
HELPER_DST="''' + _helperDst + r'''"
HELPER_SRC="$BUNDLE_PATH/Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/packages/clash_service/bin/clashyService"
HELPER_CLASH_SRC="$BUNDLE_PATH/Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/packages/clash_service/lib/libclash.dylib"
HELPER_CLASH_DST="''' + _helperClashlibDst + r'''"
LOG_FILE="''' + _logFile + r'''"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

log "========== install-helper 开始 =========="

if [ ! -f "$HELPER_SRC" ]; then
    log "❌ 找不到源二进制: $HELPER_SRC"
    exit 1
fi

mkdir -p /Library/PrivilegedHelperTools
cp -f "$HELPER_SRC" "$HELPER_DST"
chown root:wheel "$HELPER_DST"
chmod 755 "$HELPER_DST"
xattr -cr "$HELPER_DST" 2>/dev/null || true
log "helper 已安装到 $HELPER_DST"

if [ ! -f "$HELPER_CLASH_SRC" ]; then
    log "❌ 找不到 libclash.dylib: $HELPER_CLASH_SRC"
    exit 1
fi

cp -f "$HELPER_CLASH_SRC" "$HELPER_CLASH_DST"
chown root:wheel "$HELPER_CLASH_DST"
chmod 755 "$HELPER_CLASH_DST"
xattr -cr "$HELPER_CLASH_DST" 2>/dev/null || true
log "libclash.dylib 已安装到 $HELPER_CLASH_DST"

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$SERVICE_ID</string>
    <key>Program</key>
    <string>$HELPER_DST</string>
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

chown root:wheel "$PLIST_PATH"
chmod 644 "$PLIST_PATH"
log "plist 已写入 $PLIST_PATH"

if launchctl print "system/$SERVICE_ID" >/dev/null 2>&1; then
    log "卸载旧实例..."
    launchctl bootout "system/$SERVICE_ID" 2>/dev/null || true
    sleep 1
fi

launchctl bootstrap system "$PLIST_PATH" || log "bootstrap 失败，退出码 $?"
launchctl enable "system/$SERVICE_ID" 2>/dev/null || true
launchctl kickstart -kp "system/$SERVICE_ID" 2>/dev/null || log "kickstart 失败"

if launchctl print "system/$SERVICE_ID" >/dev/null 2>&1; then
    log "✅ 服务已加载"
    exit 0
else
    log "❌ 服务未加载"
    exit 1
fi
''';
  }

  static String _buildUninstallScript() {
    return r'''
#!/bin/bash
set -u

PLIST_PATH="''' + _plistPath + r'''"
SERVICE_ID="''' + _serviceId + r'''"
HELPER_DST="''' + _helperDst + r'''"
HELPER_CLASH_DST="''' + _helperClashlibDst + r'''"

if launchctl print "system/$SERVICE_ID" >/dev/null 2>&1; then
    launchctl bootout "system/$SERVICE_ID" 2>/dev/null || true
fi

rm -f "$PLIST_PATH" "$HELPER_DST" "$HELPER_CLASH_DST"
echo "已卸载 $SERVICE_ID"
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