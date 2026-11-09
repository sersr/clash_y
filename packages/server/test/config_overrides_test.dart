import 'package:server/src/server/config_overrides.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  group('applyConfigOverrides', () {
    test('replaces app owned keys with the running values', () {
      const current = '''
mixed-port: 7891
mode: global
log-level: debug
ipv6: false
allow-lan: true
dns:
  enable: true
  nameserver:
    - 223.5.5.5
tun:
  enable: true
  stack: system
proxies: []
''';
      const downloaded = '''
mixed-port: 7890
mode: rule
dns:
  enable: false
proxy-groups:
  - name: auto
    type: url-test
    proxies: [a, b]
proxies:
  - name: a
    type: ss
  - name: b
    type: ss
''';

      final merged = loadYaml(applyConfigOverrides(downloaded, current)) as Map;

      expect(merged['mixed-port'], 7891);
      expect(merged['mode'], 'global');
      expect(merged['log-level'], 'debug');
      expect(merged['ipv6'], false);
      expect(merged['allow-lan'], true);
      expect((merged['dns'] as Map)['enable'], true);
      expect((merged['tun'] as Map)['stack'], 'system');
      // Provider content survives.
      expect((merged['proxy-groups'] as List).length, 1);
      expect((merged['proxies'] as List).length, 2);
    });

    test(
      'keeps the downloaded config when the current one has no overrides',
      () {
        const downloaded = 'mode: rule\nproxies: []\n';

        expect(applyConfigOverrides(downloaded, 'proxies: []\n'), downloaded);
      },
    );

    test('rejects a downloaded document that is not a map', () {
      expect(
        () => applyConfigOverrides('- a\n- b\n', 'mode: rule\n'),
        throwsFormatException,
      );
    });
  });
}
