import 'package:file/file.dart';

import '../common.dart';

File get configYaml {
  final configDir = fs.currentDirectory
      .childDirectory(G.appSubPath)
      .childDirectory('clash_config');
  return configDir.childFile('config.yaml').absolute;
}
