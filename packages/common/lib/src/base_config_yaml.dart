import 'dart:convert';

import 'package:common/common.dart';
import 'package:nop/utils.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_writer/yaml_writer.dart';

Future<void> syncConfigDotYaml(Profile profile) async {
  final path = profile.filePath;
  if (path != configYaml.path) {
    try {
      var data = await profile.getConfigData();

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
  if (!await fs.currentDirectory.childFile(current.filePath).exists()) {
    await download(current);
  }

  final data = await current.getConfigData();

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

Future<void> writeConfigMap(String path, Map<String, dynamic> data) async {
  final file = fs.currentDirectory.childFile(path);
  await file.writeAsString(YamlWriter().write(data), flush: true);
}
