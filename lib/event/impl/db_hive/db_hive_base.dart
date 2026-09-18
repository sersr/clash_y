import 'dart:async';

import 'package:clash_y/event/repository.dart';
import 'package:path/path.dart';

import '../../base/database.dart';

mixin HiveDbMixin {
  /// document
  Paths get paths;
  String get appPath => paths.appPath;

  late ClashDatabase db;
  final _fileName = '_clash_db.nopdb';

  Future<void> init() async {
    db = ClashDatabase.open(join(appPath, _fileName));
  }

  Future<void> onClose() async {
    db.dispose();
  }
}
