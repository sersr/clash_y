String baseConfigYaml(String unixSocket) {
  return '''
# HTTP 端口
mixed-port: 7890
# SOCKS5 端口
socks-port: 7891
# Linux 及 macOS 的 redir 端口
redir-port: 7892
allow-lan: true
# Rule / Global/ Direct (默认为 Rule 模式)
mode: Rule
log-level: info

# RESTful API for clash
# external-controller: 0.0.0.0:9090
external-controller-unix: $unixSocket

experimental:
  ignore-resolve-fail: true # ignore dns resolve fail, default value is true

''';
}

Map<String, Object?> defaultDnsConfig() {
  return {
    'enable': true,
    'ipv6': false,
    'enhanced-mode': 'fake-ip',
    'fake-ip-range': '198.18.0.1/16',
    'default-nameserver': ['223.5.5.5', '1.1.1.1'],
    'nameserver': ['223.5.5.5', '1.1.1.1', '119.29.29.29'],
  };
}
