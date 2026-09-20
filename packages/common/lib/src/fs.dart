import 'package:file/file.dart';
import 'package:file/local.dart';

import '../common.dart';

const fs = LocalFileSystem();

File get configYaml {
  final configDir = fs.currentDirectory
      .childDirectory(G.appSubPath)
      .childDirectory('clash_config');
  return configDir.childFile('config.yaml');
}
