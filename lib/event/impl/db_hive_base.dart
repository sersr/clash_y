import 'dart:async';

import 'package:hive_ce/hive.dart';
import 'package:nop/nop.dart';
import 'package:path/path.dart';

import '../base/database.dart';

mixin HiveMixin on Resolve {
  String get cachePath;
  @override
  void initStateListen(add) {
    super.initStateListen(add);
    Hive.init(join(cachePath, 'hive'));
  }

  @override
  FutureOr<void> onClose() async {
    await Hive.close();
    return super.onClose();
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
  FutureOr<void> onClose() {
    db.dispose();
    return super.onClose();
  }
}
