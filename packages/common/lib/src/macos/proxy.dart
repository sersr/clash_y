import 'dart:io';

class SystemProxyManager {
  static const _networksetup = '/usr/sbin/networksetup';

  final String host;
  final int port;

  SystemProxyManager({
    this.host = '127.0.0.1',
    this.port = 7890,
  });

  /// 当前使用的网络服务
  Future<List<String>> getNetworkServices() async {
    final result = await Process.run(
      _networksetup,
      ['-listallnetworkservices'],
    );

    if (result.exitCode != 0) {
      throw Exception(
        'Failed to get network services: ${result.stderr}',
      );
    }

    final lines = (result.stdout as String)
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      return [];
    }

    return lines
        .skip(1)
        .where((e) => !e.startsWith('*'))
        .toList();
  }

  Future<ProcessResult> _run(List<String> args) {
    return Process.run(_networksetup, args);
  }

  Future<void> _runChecked(List<String> args) async {
    final result = await _run(args);

    if (result.exitCode != 0) {
      throw Exception(
        'networksetup ${args.join(' ')} failed:\n'
        '${result.stderr}',
      );
    }
  }

  /// 开启系统代理
  Future<void> enable() async {
    final services = await getNetworkServices();

    for (final service in services) {
      await _runChecked([
        '-setwebproxy',
        service,
        host,
        '$port',
      ]);

      await _runChecked([
        '-setsecurewebproxy',
        service,
        host,
        '$port',
      ]);

      await _runChecked([
        '-setwebproxystate',
        service,
        'on',
      ]);

      await _runChecked([
        '-setsecurewebproxystate',
        service,
        'on',
      ]);
    }
  }

  /// 关闭系统代理
  Future<void> disable() async {
    final services = await getNetworkServices();

    for (final service in services) {
      await _runChecked([
        '-setwebproxystate',
        service,
        'off',
      ]);

      await _runChecked([
        '-setsecurewebproxystate',
        service,
        'off',
      ]);
    }
  }

  /// 查看 HTTP 代理
  Future<String> getWebProxy(String service) async {
    final result = await _run([
      '-getwebproxy',
      service,
    ]);

    if (result.exitCode != 0) {
      throw Exception(result.stderr);
    }

    return result.stdout as String;
  }

  /// 查看 HTTPS 代理
  Future<String> getSecureWebProxy(String service) async {
    final result = await _run([
      '-getsecurewebproxy',
      service,
    ]);

    if (result.exitCode != 0) {
      throw Exception(result.stderr);
    }

    return result.stdout as String;
  }
}