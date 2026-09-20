import 'dart:async';

import 'package:clash_y/event/repository.dart';
import 'package:nop/isolate_event.dart';
import 'package:path/path.dart';

import '../../base/database.dart';

mixin DatabaseMixin on ResolveEvent {
  /// document
  Paths get paths;
  String get appPath => paths.appPath;

  late ClashDatabase db;
  final _fileName = '_clash_db.nopdb';

  @override
  FutureOr<void> onInit() {
    db = ClashDatabase.open(join(appPath, _fileName));
  }

  @override
  Future<void> onClose() async {
    db.dispose();
  }
}
