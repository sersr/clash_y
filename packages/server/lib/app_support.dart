import 'dart:io';

import 'package:path/path.dart' as p;

String get clashyApplicationSupportDirectory {
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    throw StateError('HOME is not set for the macOS service process');
  }
  return p.join(home, 'Library', 'Application Support', 'Clashy');
}

String get clashyApplicationCacheDirectory {
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    throw StateError('HOME is not set for the macOS service process');
  }
  return p.join(home, 'Library', 'Caches', 'clashy');
}
