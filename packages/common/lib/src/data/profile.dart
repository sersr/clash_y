part of '_g.dart';

extension ProfileExt on Profile {
  String get filePath {
    if (url case var url?) {
      return G.getCacheFile(url).path;
    }
    return '';
  }

  Future<Map<String, dynamic>> getConfigData() async {
    final data = await _getConfigData();
    Log.w(configYaml.path);
    _updateProfileData(data);
    return data;
  }

  Future<Map<String, dynamic>> _getConfigData() async {
    final js = JSInterpreter();
    Map<String, dynamic> data = {};
    try {
      data = await getConfigMap(filePath);
      final script = SettingsHive.getScript(scriptId);
      if (script == null) return data;

      final scriptErrors = <String?>[];
      js.eval(script.script);

      if (scriptErrors.isNotEmpty) {
        throw FormatException(
          scriptErrors.first ?? 'unable to evaluate profile script',
        );
      }

      js.setGlobal('profileConfig', data);

      final resultErrors = <String?>[];
      final value = js.evalToDart('main(profileConfig);');

      if (resultErrors.isNotEmpty) {
        throw FormatException(
          resultErrors.first ?? 'unable to execute profile script',
        );
      }
      if (value == null) {
        throw const FormatException('profile script returned no config');
      }

      return jsonDecode(value);
    } catch (e) {
      Log.e(e);
      return data;
    } finally {
      // js.close();
    }
  }
}

void _updateProfileData(Map<String, dynamic> data) {
  final unixSocketPath = G.unixSocketPath;

  if (defaultTargetPlatform == .windows) {
    data['external-controller-pipe'] = unixSocketPath;
    data.remove('external-controller-unix');
  } else {
    data.remove('external-controller-pipe');
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
