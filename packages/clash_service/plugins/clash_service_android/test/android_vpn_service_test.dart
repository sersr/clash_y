import 'dart:io' show Platform;

import 'package:clash_service_android/clash_service_android.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports support only on Android', () {
    expect(AndroidVpnService.isSupported, Platform.isAndroid);
  });

  test('start and stop are no-ops off Android', () async {
    // The guard must run before any JNI handle is touched, otherwise importing
    // the plugin on desktop would initialise a JVM that is not there.
    expect(await start('/data/local/tmp'), Platform.isAndroid);
    expect(await stop(), Platform.isAndroid);
  });

  test('an empty configuration directory is rejected', () async {
    expect(await AndroidVpnService.start('   '), isFalse);
  });
}
