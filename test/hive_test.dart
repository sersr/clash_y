import 'package:common/common.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test("hive type(runtime)", () async {
    await G.initTest();

    for (var item in Hives.items) {
      item.al;
    }
  });
}
