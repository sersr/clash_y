import 'package:hive_ce/hive.dart';

abstract final class HiveBoxKey {
  static const config = 'config';
}

abstract final class Hives {
  static Box get config => Hive.box(HiveBoxKey.config);

  static Future<void> init(String path) {
    Hive.init(path);
    return [Hive.openBox(HiveBoxKey.config)].wait;
  }
}
