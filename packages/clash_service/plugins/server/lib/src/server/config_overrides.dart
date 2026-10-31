import 'dart:convert';

import 'package:nop/nop.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// Top-level keys owned by the app.
///
/// The app writes the device specific settings (listening ports, TUN, DNS,
/// controller socket...) into `config.yaml`; subscription updates must keep
/// those values instead of whatever the provider ships.
const configOverrideKeys = [
  'external-controller-unix',
  'external-controller-pipe',
  'log-level',
  'mixed-port',
  'mode',
  'ipv6',
  'allow-lan',
  'tun',
  'dns',
];

/// Keeps the [configOverrideKeys] of [current] in [downloaded].
String applyConfigOverrides(String downloaded, String current) {
  final currentData = loadYaml(current);
  if (currentData is! Map) return downloaded;
  final downloadedData = loadYaml(downloaded);
  if (downloadedData is! Map) {
    throw const FormatException('downloaded config is not a YAML map');
  }

  final editor = YamlEditor(downloaded);
  for (final key in configOverrideKeys) {
    if (!currentData.containsKey(key)) continue;
    final value = jsonDecode(jsonEncode(currentData[key]));
    try {
      editor.update([key], value);
    } catch (e) {
      Log.e('apply config override "$key" failed: $e');
    }
  }
  return editor.toString();
}
