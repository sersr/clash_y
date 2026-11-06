import 'dart:convert';

import 'package:common/common.dart';
import 'package:flutter/foundation.dart';
import 'package:nop/utils.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_writer/yaml_writer.dart';

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

Future<void> saveConfigPath(String path) async {
  if (path != configYaml.path) {
    try {
      final data = await getConfigMap(path);

      await configYaml.writeAsString(YamlWriter().write(data));
    } catch (e) {
      Log.e(e);
    }
  }
}

Future<void> _sync() async {
  try {
    // if (await configYaml.exists()) return;
    final current = BaseConfig.currentProfile.value.url;
    if (current == null) return;
    final paths = Paths.g();
    await saveConfigPath(paths.getCacheFile(current).path);
  } catch (e) {
    Log.e(e);
  }
}

Map<String, dynamic> yamlToJson(String yaml) {
  return jsonDecode(jsonEncode(loadYaml(yaml)));
}

Future<String> initConfigPath() async {
  await _sync();
  final file = configYaml;

  final configDir = file.parent;
  final unixSocketPath = BaseConfig.unixSockPath.value;

  var data = {};
  if (await file.exists()) {
    data = yamlToJson(await file.readAsString());
  } else {
    await file.create(recursive: true);
  }

  if (defaultTargetPlatform == .windows) {
    data['external-controller-pipe'] = unixSocketPath;
  } else {
    data['external-controller-unix'] = unixSocketPath;
  }

  data['log-level'] = SettingsHive.logLevel.value.name;
  data['mixed-port'] = SettingsHive.mixedPort.value;
  data['mode'] = SettingsHive.mode.value.name;
  data['ipv6'] = SettingsHive.ipv6.value;
  data['allow-lan'] = SettingsHive.allowLan.value;

  final tun = data['tun'] ??= <String, dynamic>{};
  tun
    ..['enable'] = SettingsHive.tunEnabled.value
    ..['stack'] = SettingsHive.tunStack.value.name
    ..['device'] = 'clashy';

  data['dns'] = defaultDnsConfig();

  try {
    await file.writeAsString(YamlWriter().write(data));
  } catch (e) {
    Log.e('error: $e');
  }

  // copy(v);
  return configDir.path;
}

Future<Map<String, dynamic>> getConfigMap(String path) async {
  final file = fs.currentDirectory.childFile(path);
  final unixSocketPath = BaseConfig.unixSockPath.value;

  var data = <String, dynamic>{};
  if (await file.exists()) {
    data = yamlToJson(await file.readAsString());
  } else {
    await file.create(recursive: true);
  }

  if (defaultTargetPlatform == .windows) {
    data['external-controller-pipe'] = unixSocketPath;
  } else {
    data['external-controller-unix'] = unixSocketPath;
  }

  data['log-level'] = SettingsHive.logLevel.value.name;
  data['mixed-port'] = SettingsHive.mixedPort.value;
  data['mode'] = SettingsHive.mode.value.name;
  data['ipv6'] = SettingsHive.ipv6.value;
  data['allow-lan'] = SettingsHive.allowLan.value;

  final tun = data['tun'] ??= <String, dynamic>{};
  tun
    ..['enable'] = SettingsHive.tunEnabled.value
    ..['stack'] = SettingsHive.tunStack.value.name
    ..['device'] = 'clashy';

  data['dns'] = defaultDnsConfig();

  // copy(v);
  return data;
}

Future<void> writeConfigMap(String path, Map<String, dynamic> data) async {
  final file = fs.currentDirectory.childFile(path);
  await file.writeAsString(YamlWriter().write(data), flush: true);
}
