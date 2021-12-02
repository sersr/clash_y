import '../../data/data.dart';
import 'database.dart';

class ConfigName {
  ConfigName({
    required this.name,
    required this.updateInterval,
    required this.url,
    required this.updateTime,
  });
  final String url;
  final String name;
  final int updateInterval;
  final DateTime updateTime;
}

class ConfigsCurrent {
  const ConfigsCurrent(this.current, this.tables);
  static const none = ConfigsCurrent('', []);
  final List<ConfigTable> tables;
  final String current;
}

class ProxiesData {
  const ProxiesData({required this.history, required this.proxies});
  final List<History> history;
  final List<ProxyItem> proxies;
}

bool proxyHasData(ProxyItem data) {
  return data.all != null && data.name != null && data.type != null;
}

class ConfigsData {
  ConfigsData({
    this.allowLan,
    this.logLevel,
    this.mode,
    this.port,
    this.redirPort,
    this.socksPort,
  });
  final int? port;
  final int? socksPort;
  final String? redirPort;
  final bool? allowLan;
  final String? mode;
  final String? logLevel;

  Map<String, Object> get body {
    final _body = <String, Object>{};
    if (port != null) _body['port'] = port!;
    if (socksPort != null) _body['socks-port'] = socksPort!;
    if (redirPort != null) _body['redir-port'] = redirPort!;
    if (allowLan != null) _body['allow-lan'] = allowLan!;
    if (mode != null) _body['mode'] = mode!;
    if (logLevel != null) _body['log-level'] = logLevel!;

    return _body;
  }
}
