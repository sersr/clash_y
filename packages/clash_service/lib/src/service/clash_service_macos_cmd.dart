import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:server/server.dart' show clashSocket;
import 'package:server/tray_asset.dart';

/// macOS 服务安装/控制。
///
/// 守护进程跑在 system 域（`/Library/LaunchDaemons`、root），自己创建并配置
/// utun，不再有独立的 TUN helper；菜单栏托盘是用户 GUI 会话里的
/// `/Library/LaunchAgents` Agent，由 launchd 在每个登录用户里启动——daemon
/// 在 system 域没有 WindowServer 连接，画不出菜单栏。
abstract final class MacOSServiceProcess {
  static const _serviceLabel = 'com.aote.clashy.service';
  static const _trayLabel = 'com.aote.clashy.tray';

  static const _daemonPlistPath =
      '/Library/LaunchDaemons/com.aote.clashy.service.plist';

  /// 托盘 Agent 放在当前用户的 `~/Library/LaunchAgents`：它只在登录会话里跑，
  /// 也不该为了 app 换位置去要管理员授权。
  static String get _trayPlistPath => p.join(
    Platform.environment['HOME'] ?? '',
    'Library/LaunchAgents',
    '$_trayLabel.plist',
  );

  /// 早期版本把托盘 Agent 装在 root 拥有的 `/Library/LaunchAgents`；同一 label
  /// 两处并存会被加载两次，升级时清掉。
  static const _legacyTrayPlistPath =
      '/Library/LaunchAgents/com.aote.clashy.tray.plist';

  /// 服务二进制由 root 拥有的副本；不直接执行 app bundle 里的文件，避免用户
  /// 替换 bundle 内容后拿到 root 权限。
  ///
  /// 不放进 `/Library/PrivilegedHelperTools`：那里的可执行文件会由
  /// AppleSystemPolicy 评估，开发构建的 ad-hoc 签名会被直接拒绝执行
  /// （`ASP: Security policy would not allow process`），launchd 每 10 秒拉起一次
  /// 又立刻失败，应用看到的永远是「没在运行」，于是每次启动都重新提权安装、
  /// 每次都弹密码。放在 `Clashy` 自己的 root 目录里同样只有 root 能写。
  static const _installedServicePath =
      '/Library/Application Support/Clashy/bin/clashyService';

  /// 早期版本把服务副本装在这里；安装时顺手清掉，否则升级后仍会被 launchd
  /// 当作另一个可执行文件反复拉起。
  static const _legacyInstalledServicePath =
      '/Library/PrivilegedHelperTools/com.aote.clashy.service';

  static const _serviceRelativePath =
      'Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/'
      'packages/clash_service/bin/clashyService';

  static String get _bundlePath {
    final executable = Platform.resolvedExecutable;
    final marker = executable.indexOf('/Contents/MacOS/');
    if (marker < 0) {
      throw StateError('无法解析 App bundle 路径: $executable');
    }
    return executable.substring(0, marker);
  }

  static String get _servicePath => p.join(_bundlePath, _serviceRelativePath);

  static String get _trayPath =>
      p.join(p.dirname(_servicePath), clashTrayExecutableName);

  static Future<bool> isInstalled() async {
    try {
      await _validateBundleAssets();
    } on FileSystemException {
      return false;
    } on StateError {
      return false;
    }
    return File(_daemonPlistPath).existsSync() &&
        File(_installedServicePath).existsSync();
  }

  /// 托盘进程是否在跑（按 launchd job 状态判断）。
  static Future<bool> _isTrayRunning(int uid) async {
    final status = await _launchctlPrint('gui/$uid/$_trayLabel');
    return status != null && RegExp(r'\bstate = running\b').hasMatch(status);
  }

  /// 确保托盘在跑：job 没加载就先 bootstrap，加载了但没跑就 kickstart。
  ///
  /// App 每次打开都要有托盘——即使上次是用户手动退出的。
  static Future<void> _ensureTrayRunning(int uid, String plist) async {
    final domainPath = 'gui/$uid/$_trayLabel';
    if (await _launchctlPrint(domainPath) == null) {
      await _installTrayAgent(uid: uid, plist: plist);
      return;
    }
    if (await _isTrayRunning(uid)) return;
    await Process.run('/bin/launchctl', ['kickstart', domainPath]);
  }

  static Future<bool> isRunning() async {
    final status = await _launchctlPrint('system/$_serviceLabel');
    return status != null && RegExp(r'\bstate = running\b').hasMatch(status);
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

  static Future<void> install({
    required String clashSocketPath,
    bool forceRestart = false,
  }) async {
    await _validateBundleAssets();
    final uid = await _currentUid();
    final expectedDaemon = _daemonPlist(clashSocketPath, uid);
    final expectedTray = _trayPlist(clashSocketPath);
    final bundledHash = await _sha256(_servicePath);
    final installedHash = await _sha256(_installedServicePath);
    final legacyTrayPresent = File(_legacyTrayPlistPath).existsSync();
    final plistChanged =
        await _readFileIfExists(_daemonPlistPath) != expectedDaemon;
    final daemonLoaded = await _launchctlPrint('system/$_serviceLabel') != null;

    final reinstallDaemon =
        forceRestart ||
        plistChanged ||
        bundledHash == null ||
        bundledHash != installedHash ||
        !daemonLoaded;
    final reinstallTray =
        forceRestart ||
        legacyTrayPresent ||
        await _readFileIfExists(_trayPlistPath) != expectedTray;

    // 托盘属于当前用户，写自己的 Agent 不需要 root；守护进程的副本和
    // `/Library/LaunchDaemons` 才需要。所以 app 换了个位置（Debug / Release /
    // 挪过目录的 .app）只会重写用户 plist，不该再弹管理员密码。
    if (reinstallDaemon) {
      try {
        await _runElevated(
          _daemonInstallScript(
            uid: uid,
            daemonPlist: expectedDaemon,
            reloadJob: plistChanged || !daemonLoaded,
          ),
        );
      } on ProcessException {
        // 另一个实例可能已经把它注册上了：只要 job 在，就不算安装失败。
        if (await _launchctlPrint('system/$_serviceLabel') == null) rethrow;
      }
    } else {
      // 开机时 launchd 可能还在拉起服务，先给一小段时间，等不到再判断。
      await _waitForServiceSocket(const Duration(seconds: 3));
      if (!await isRunning() && !await _isServiceSocketReady()) {
        // job 还加载着但进程没在跑（崩溃 / 被手动停过）。没有 KeepAlive 时
        // launchd 不会自己拉回来，这里补一次 kickstart；system 域需要 root。
        await _runElevated('''
set -eu
/bin/launchctl kickstart -k system/$_serviceLabel
''');
        await _waitUntilRunning();
      } else if (legacyTrayPresent) {
        // 只清掉老版本留在 root 目录里的托盘 Agent，不重启正在跑的守护进程。
        await _runElevated(_legacyTrayCleanupScript(uid));
      }
    }
    if (reinstallDaemon || reinstallTray) {
      await _installTrayAgent(uid: uid, plist: expectedTray);
    } else {
      // 打开 App 就要有托盘：用户上次手动退出过，这里也要再拉起来。
      await _ensureTrayRunning(uid, expectedTray);
    }

    if (reinstallDaemon) {
      await _waitUntilRunning();
    } else {
      await _waitForServiceSocket(const Duration(seconds: 5));
    }
  }

  /// 老版本把托盘 Agent 装在这里；同一 label 两处并存会被加载两次。
  static String _legacyTrayCleanupScript(int uid) =>
      '''
set -eu
/bin/launchctl bootout gui/$uid/$_trayLabel >/dev/null 2>&1 || true
/bin/rm -f ${_shellQuote(_legacyTrayPlistPath)}
''';

  /// 托盘 Agent 装在当前用户的 `~/Library/LaunchAgents`：菜单栏进程本来就在
  /// 用户会话里跑，没有理由占 root 拥有的 `/Library/LaunchAgents`。
  static Future<void> _installTrayAgent({
    required int uid,
    required String plist,
  }) async {
    final file = File(_trayPlistPath);
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    if (await _readFileIfExists(_trayPlistPath) != plist) {
      await file.writeAsString(plist);
    }
    final domainPath = 'gui/$uid/$_trayLabel';
    await Process.run('/bin/launchctl', ['bootout', domainPath]);
    await _waitUntilUnloaded(domainPath);
    await _bootstrap('gui/$uid', _trayPlistPath);
    // bootstrap 只负责加载 job，这里再 kickstart 一次，装上就能立刻看到托盘。
    await Process.run('/bin/launchctl', ['kickstart', 'gui/$uid/$_trayLabel']);
  }

  /// 守护进程安装脚本：装 root 拥有的服务副本、写 daemon plist。
  ///
  /// 只有 plist 内容变了（或 job 根本没加载）才走 `bootout` + `bootstrap`：
  /// `bootout` 是异步的，job 还没从 `system` 域消失就 bootstrap 同一个 label，
  /// launchd 会回 `Bootstrap failed: 5: Input/output error`。所以要么等到它真的
  /// 消失，要么干脆只换二进制并 `kickstart -k` 重启，绕开这段竞态。
  static String _daemonInstallScript({
    required int uid,
    required String daemonPlist,
    required bool reloadJob,
  }) {
    const daemonPlistTemp = '/tmp/clashy-service.plist';
    final binDir = p.dirname(_installedServicePath);
    final applyJob = reloadJob
        ? '''
/bin/launchctl bootout system/$_serviceLabel >/dev/null 2>&1 || true
i=0
while /bin/launchctl print system/$_serviceLabel >/dev/null 2>&1; do
  i=\$((i + 1))
  [ "\$i" -lt 300 ] || break
  /bin/sleep 0.1
done
/bin/launchctl enable system/$_serviceLabel
n=0
until /bin/launchctl bootstrap system ${_shellQuote(_daemonPlistPath)}; do
  n=\$((n + 1))
  if [ "\$n" -ge 6 ]; then
    # 另一个 app 实例可能刚好把它注册上了，已加载就算成功。
    /bin/launchctl print system/$_serviceLabel >/dev/null 2>&1 && exit 0
    exit 1
  fi
  /bin/sleep 0.5
done
/bin/launchctl kickstart -k system/$_serviceLabel
'''
        : '''
/bin/launchctl kickstart -k system/$_serviceLabel
''';
    return '''
set -eu
/bin/mkdir -p ${_shellQuote(binDir)}
/usr/sbin/chown root:wheel ${_shellQuote(binDir)}
/bin/chmod 755 ${_shellQuote(binDir)}
/usr/bin/install -o root -g wheel -m 755 ${_shellQuote(_servicePath)} ${_shellQuote(_installedServicePath)}
/bin/mkdir -p /Library/LaunchDaemons
printf '%s' ${_shellQuote(daemonPlist)} > ${_shellQuote(daemonPlistTemp)}
/usr/sbin/chown root:wheel ${_shellQuote(daemonPlistTemp)}
/bin/chmod 644 ${_shellQuote(daemonPlistTemp)}
/bin/mv -f ${_shellQuote(daemonPlistTemp)} ${_shellQuote(_daemonPlistPath)}
/bin/rm -f ${_shellQuote(_legacyInstalledServicePath)}
/bin/launchctl bootout gui/$uid/$_trayLabel >/dev/null 2>&1 || true
/bin/rm -f ${_shellQuote(_legacyTrayPlistPath)}
$applyJob''';
  }

  /// 守护进程以 root 运行，控制面只对安装它的那个桌面用户（以及 root）放行：
  /// `--allowed-uid` 让服务在 accept 时用 peer credentials 校验客户端 uid。
  static String _daemonPlist(String clashSocketPath, int uid) =>
      '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <!-- 守护进程随 launchd 在开机时启动一次（RunAtLoad）。
       不带 KeepAlive：手动停掉后 launchd 不会把它拉回来。
       system 域 job 的 kickstart 需要 root，所以不能指望 App 在开机后
       无密码地把服务拉起来。 -->
  <key>Label</key>
  <string>$_serviceLabel</string>
  <key>ProgramArguments</key>
  <array>
    <string>${_xmlEscape(_installedServicePath)}</string>
    <string>--service-socket</string>
    <string>${_xmlEscape(clashSocket)}</string>
    <string>--clash-socket</string>
    <string>${_xmlEscape(clashSocketPath)}</string>
    <string>--allowed-uid</string>
    <string>$uid</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
''';

  static String _trayPlist(String clashSocketPath) =>
      '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$_trayLabel</string>
  <key>ProgramArguments</key>
  <array>
    <string>${_xmlEscape(_trayPath)}</string>
    <string>--app</string>
    <string>${_xmlEscape(_bundlePath)}</string>
    <string>--service-socket</string>
    <string>${_xmlEscape(clashSocket)}</string>
    <string>--clash-socket</string>
    <string>${_xmlEscape(clashSocketPath)}</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${_xmlEscape(_bundlePath)}</string>
  <key>LimitLoadToSessionType</key>
  <string>Aqua</string>
  <!-- 登录/重启时自动启动托盘；但不带 KeepAlive，用户手动退出后
       launchd 不会再把它拉回来（同一会话内保持退出状态）。 -->
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
''';

  static Future<void> stop() async {
    if (!await isRunning()) return;
    await _runElevated('''
set -eu
/bin/launchctl bootout system/$_serviceLabel >/dev/null 2>&1 || true
''');
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline)) {
      if (!await isRunning() && !await _isServiceSocketReady()) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw StateError('macOS clashyService did not stop after launchd bootout.');
  }

  static Future<void> uninstall() async {
    await _removeTrayAgent();
    final uid = await _currentUid();
    await _runElevated('''
set -eu
/bin/launchctl bootout system/$_serviceLabel >/dev/null 2>&1 || true
/bin/launchctl disable system/$_serviceLabel >/dev/null 2>&1 || true
/bin/launchctl bootout gui/$uid/$_trayLabel >/dev/null 2>&1 || true
/bin/launchctl disable gui/$uid/$_trayLabel >/dev/null 2>&1 || true
/bin/rm -f ${_shellQuote(_daemonPlistPath)} ${_shellQuote(_installedServicePath)} ${_shellQuote(_legacyInstalledServicePath)} ${_shellQuote(_legacyTrayPlistPath)}
''');
  }

  /// 卸载时先清用户自己的托盘 Agent：这一步不需要 root，root 脚本删不掉
  /// 用户目录里的文件时也不会留下半卸载状态。
  static Future<void> _removeTrayAgent() async {
    final uid = await _currentUid();
    await Process.run('/bin/launchctl', ['bootout', 'gui/$uid/$_trayLabel']);
    await _waitUntilUnloaded('gui/$uid/$_trayLabel');
    final file = File(_trayPlistPath);
    if (await file.exists()) await file.delete();
  }

  static Future<int> _currentUid() async {
    final result = await Process.run('/usr/bin/id', ['-u']);
    if (result.exitCode != 0) {
      throw ProcessException(
        '/usr/bin/id',
        const ['-u'],
        '${result.stderr}',
        result.exitCode,
      );
    }
    final uid = (result.stdout as String).trim();
    if (!RegExp(r'^[1-9]\d*$').hasMatch(uid)) {
      throw FormatException('Unexpected user ID for LaunchAgent: $uid');
    }
    return int.parse(uid);
  }

  static Future<String?> _launchctlPrint(String domain) async {
    final result = await Process.run('/bin/launchctl', ['print', domain]);
    if (result.exitCode != 0) return null;
    return result.stdout as String;
  }

  /// `bootout` 是异步的：job 还没从目标域里消失就 `bootstrap` 同一个 label，
  /// launchd 会直接回 `Bootstrap failed: 5: Input/output error`。所以先等它真的
  /// 卸载，注册本身再留几次重试。
  static Future<void> _bootstrap(String domain, String plistPath) async {
    const attempts = 6;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      final result = await Process.run('/bin/launchctl', [
        'bootstrap',
        domain,
        plistPath,
      ]);
      if (result.exitCode == 0) return;
      if (attempt == attempts) {
        throw ProcessException(
          '/bin/launchctl',
          ['bootstrap', domain, plistPath],
          '${result.stderr}',
          result.exitCode,
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  static Future<void> _waitUntilUnloaded(String domainPath) async {
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (DateTime.now().isBefore(deadline)) {
      if (await _launchctlPrint(domainPath) == null) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  /// 通过 osascript 的 administrator 授权执行脚本，与其他平台的提权入口一致。
  static Future<void> _runElevated(String script) async {
    final encoded = base64Encode(utf8.encode(script));
    final command = "printf '%s' '$encoded' | /usr/bin/base64 -D | /bin/sh";
    final appleScript =
        'do shell script "${command.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}" '
        'with administrator privileges';
    final result = await Process.run('/usr/bin/osascript', ['-e', appleScript]);
    if (result.exitCode != 0) {
      throw ProcessException(
        '/usr/bin/osascript',
        const ['-e', '<installer script>'],
        '${result.stderr}',
        result.exitCode,
      );
    }
  }

  static String _shellQuote(String value) =>
      "'${value.replaceAll("'", "'\"'\"'")}'";

  static Future<String?> _readFileIfExists(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  static Future<String?> _sha256(String path) async {
    if (!File(path).existsSync()) return null;
    final result = await Process.run('/usr/bin/shasum', ['-a', '256', path]);
    if (result.exitCode != 0) {
      throw ProcessException(
        '/usr/bin/shasum',
        ['-a', '256', path],
        '${result.stderr}',
        result.exitCode,
      );
    }
    return (result.stdout as String).split(' ').first;
  }

  static String _xmlEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static Future<void> _waitUntilRunning() async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      if (await isRunning() && await _isServiceSocketReady()) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    throw StateError('macOS clashyService did not become ready.');
  }

  /// 已装好时不报错地等一会儿：给 launchd 自己拉起的进程一点时间，等不到就
  /// 把失败留给后续的连接错误，而不是把「服务没起来」放大成一次提权弹窗。
  static Future<void> _waitForServiceSocket(Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await _isServiceSocketReady()) return;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  static Future<bool> _isServiceSocketReady() async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress(clashSocket, type: InternetAddressType.unix),
        0,
        timeout: const Duration(milliseconds: 500),
      );
      return true;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  static Future<void> _validateBundleAssets() async {
    final bundlePath = p.normalize(p.absolute(_bundlePath));
    if (!p.basename(bundlePath).endsWith('.app')) {
      throw StateError('macOS service requires an app bundle');
    }

    final assets = [_servicePath, _trayPath];
    final checkedPaths = <String>{};
    for (final assetPath in assets) {
      final path = p.normalize(p.absolute(assetPath));
      if (!p.isWithin(bundlePath, path)) {
        throw StateError(
          'macOS service asset is outside the app bundle: $path',
        );
      }

      for (final current in _pathComponents(path)) {
        final type = await FileSystemEntity.type(current, followLinks: false);
        if (type == FileSystemEntityType.link ||
            type == FileSystemEntityType.notFound) {
          throw StateError(
            'macOS service path is missing or contains a symlink: $current',
          );
        }
        checkedPaths.add(current);
      }

      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw StateError('macOS service asset is missing: $path');
      }
    }

    final modes = await _readModes(checkedPaths.toList());
    for (final assetPath in assets) {
      final path = p.normalize(p.absolute(assetPath));
      for (final current in _pathComponents(path)) {
        final mode = modes[current];
        if (mode == null) {
          throw StateError('Missing permissions for service path: $current');
        }
        final insideBundle =
            current == bundlePath || p.isWithin(bundlePath, current);
        if (insideBundle && (mode & 0x12) != 0) {
          throw StateError(
            'macOS service path must not be writable by other users: $current',
          );
        }
        if (current == path && (mode & 0x40) == 0) {
          throw StateError('macOS service executable is not executable: $path');
        }
      }
    }
  }

  static List<String> _pathComponents(String path) {
    var current = '/';
    return p.relative(path, from: '/').split('/').map((component) {
      current = p.join(current, component);
      return current;
    }).toList();
  }

  static Future<Map<String, int>> _readModes(List<String> paths) async {
    final arguments = ['-f', '%Lp', ...paths];
    final result = await Process.run('/usr/bin/stat', arguments);
    if (result.exitCode != 0) {
      throw ProcessException(
        '/usr/bin/stat',
        arguments,
        '${result.stderr}',
        result.exitCode,
      );
    }
    final permissions = (result.stdout as String).trim().split('\n');
    if (permissions.length != paths.length) {
      throw FormatException(
        'Unexpected stat output for ${paths.length} paths: ${result.stdout}',
      );
    }
    return {
      for (var index = 0; index < paths.length; index++)
        paths[index]: _parseMode(paths[index], permissions[index]),
    };
  }

  static int _parseMode(String path, String permissions) {
    if (!RegExp(r'^[0-7]{3,4}$').hasMatch(permissions)) {
      throw FormatException('Unexpected stat output for $path: $permissions');
    }
    return int.parse(permissions, radix: 8);
  }
}
