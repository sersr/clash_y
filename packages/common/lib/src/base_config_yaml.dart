import 'dart:convert';

import 'package:common/common.dart';
import 'package:flutter/foundation.dart';
import 'package:yaml/yaml.dart';

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

Future<String> initConfigPath() async {
  final configDir = fs.currentDirectory
      .childDirectory(G.appSubPath)
      .childDirectory('clash_config');
  final file = configDir.childFile('config.yaml');
  final unixSocketPath = BaseConfig.unixSockPath.value;

  var data = {};
  if (await file.exists()) {
    data = jsonDecode(jsonEncode(loadYaml(await file.readAsString()))) as Map;
  } else {
    await file.create(recursive: true);
  }

  if (defaultTargetPlatform == .windows) {
    data['external-controller-pipe'] = unixSocketPath;
  } else {
    data['external-controller-unix'] = unixSocketPath;
  }

  data['log-level'] = SettingsHive.logLevel.value.name;
  data['mixed-port'] = SettingsHive.mixedProt.value;
  data['mode'] = SettingsHive.mode.value.name;
  data['ipv6'] = SettingsHive.ipv6.value;
  data['allow-lan'] = SettingsHive.allowLan.value;

  final tun = data['tun'] ??= <String, dynamic>{};
  tun
    ..['enable'] = SettingsHive.tunEnabled.value
    ..['stack'] = SettingsHive.tunStack.value.name
    ..['device'] = 'clashy';

  data['dns'] = defaultDnsConfig();
  final v = YamlUtils.edit(jsonEncode(data)).toString();
  await file.writeAsString(v);

  // copy(v);
  return configDir.path;
}
