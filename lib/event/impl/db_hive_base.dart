import 'dart:async';

import 'package:hive/hive.dart';
import 'package:nop_db/nop_db.dart';
import 'package:path/path.dart';
import 'package:utils/utils.dart';

import '../base/database.dart';

mixin HiveMixin on ListenMixin {
  String get cachePath;
  @override
  void initStateListen(add) {
    super.initStateListen(add);
    Hive.init(join(cachePath, 'hive'));
  }
}

mixin DatabaseMixin on Resolve {
  late ClashDatabase db;
  String get appPath;
  final _fileName = '_clash_db.nopdb';
  @override
  void initStateListen(add) {
    super.initStateListen(add);
    db = ClashDatabase.open(join(appPath, _fileName));
  }

  @override
  FutureOr<bool> onClose() {
    db.dispose();
    return super.onClose();
  }
}
