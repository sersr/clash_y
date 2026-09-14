import 'dart:async';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:hive_ce/hive.dart';
import 'package:nop/nop.dart';
import 'package:path/path.dart';

import '../../base/database.dart';

final class _IsolateNameServer implements IsolateNameServer {
  @override
  SendPort? lookupPortByName(String name) {
    return ui.IsolateNameServer.lookupPortByName(name);
  }

  @override
  bool registerPortWithName(port, String name) {
    return ui.IsolateNameServer.registerPortWithName(port, name);
  }

  @override
  bool removePortNameMapping(String name) {
    return ui.IsolateNameServer.removePortNameMapping(name);
  }
}

mixin HiveMixin on Resolve {
  /// document
  String get appPath;
  String get appCachePath => join(appPath, 'caches');

  @override
  void initStateListen(add) {
    final f = IsolatedHive.init(
      join(appPath, 'caches', 'hive'),
      isolateNameServer: _IsolateNameServer(),
    );

    final list = <String>[];

    initOpenBox(list.add);
    add(f.then((_) => list.map((e) => IsolatedHive.openBox(e)).wait));
    super.initStateListen(add);
  }

  void initOpenBox(void Function(String name) add) {}

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
