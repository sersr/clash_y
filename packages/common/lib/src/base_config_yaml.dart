import 'dart:convert';

import 'package:common/common.dart';
import 'package:flutter/foundation.dart';
import 'package:nop/utils.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_writer/yaml_writer.dart';

const _geoRulesCdnBaseUrl =
    'https://cdn.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release';
const _defaultGeoXUrls = <String, String>{
  'geoip': '$_geoRulesCdnBaseUrl/geoip.dat',
  'geosite': '$_geoRulesCdnBaseUrl/geosite.dat',
  'mmdb': '$_geoRulesCdnBaseUrl/geoip.metadb',
  'asn': '$_geoRulesCdnBaseUrl/GeoLite2-ASN.mmdb',
};

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

Future<void> syncConfigDotYaml(Profile profile) async {
  final path = profile.filePath;
  if (path != configYaml.path) {
    try {
      var data = await profile.getConfigData();
      _updateProfileData(data);

      await configYaml.writeAsString(YamlWriter().write(data));
    } catch (e) {
      Log.e(e);
    }
  }
}

Map<String, dynamic> yamlToJson(String yaml) {
  final v = loadYaml(yaml);
  final v1 = jsonEncode(v);
  return jsonDecode(v1);
}

Future<String> initConfigPath(Future Function(Profile profile) download) async {
  final current = BaseConfig.currentProfileData.value;

  final file = configYaml;
  final configDir = file.parent;
  if (!await file.exists()) {
    await download(current);
  }

  final data = await current.getConfigData();
  _updateProfileData(data);

  try {
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    await file.writeAsString(YamlWriter().write(data));
  } catch (e) {
    Log.e('error: $e');
  }

  return configDir.path;
}

Future<Map<String, dynamic>> getConfigMap(String path) async {
  final file = fs.currentDirectory.childFile(path);

  var data = <String, dynamic>{};
  if (await file.exists()) {
    data = yamlToJson(await file.readAsString());
  }

  // copy(v);
  return data;
}

void _updateProfileData(Map<String, dynamic> data) {
  final unixSocketPath = G.unixSocketPath;

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
  data['geox-url'] = _defaultGeoXUrls;

  final tun = data['tun'] ??= <String, dynamic>{};
  tun
    ..['enable'] = SettingsHive.tunEnabled.value
    ..['stack'] = SettingsHive.tunStack.value.name
    ..['device'] = 'clashy';

  data['dns'] = defaultDnsConfig();
}

Future<void> writeConfigMap(String path, Map<String, dynamic> data) async {
  final file = fs.currentDirectory.childFile(path);
  await file.writeAsString(YamlWriter().write(data), flush: true);
}
