import 'dart:io';

import 'package:file/local.dart' as f;
import 'package:path/path.dart' as p; // 可选，用于路径拼接

const fs = f.LocalFileSystem();

void main(List<String> args) async {
  print(args);

  var configDir = args.firstOrNull ?? await _defaultDir();

  if (configDir.isEmpty) {
    print("error: configDir is empty.");
    return;
  }

  final current = Platform.resolvedExecutable;
  final file = fs.currentDirectory.childFile(current);
  final dir = p.join(file.parent.path, 'clash');

  print('dir: $configDir');
  final res = await Process.start(dir, ['-d', configDir]);
  stderr.addStream(res.stderr);
  stdout.addStream(res.stdout);
  await res.exitCode;
}

Future<String> _defaultDir() async {
  if (Platform.isMacOS) {
    final home = Platform.environment['HOME'];
    if (home != null) {
      // 用户级数据目录
      final appSupportDir = Directory(
        p.join(home, 'Library', 'Application Support', 'clashy'),
      );
      if (!await appSupportDir.exists()) {
        await appSupportDir.create(recursive: true);
      }
      return appSupportDir.path;
    }
  } else if (Platform.isWindows) {
    final appDataPath = Platform.environment['APPDATA']; // 获取 %APPDATA%
    if (appDataPath != null) {
      final appDir = Directory(p.join(appDataPath, 'clashy'));
      if (!await appDir.exists()) {
        await appDir.create(recursive: true);
      }
      return appDir.path;
    }
  }
  return '';
}
