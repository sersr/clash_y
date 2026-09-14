import 'dart:io';

import 'package:nop/nop.dart';

import 'unix_socket_http.dart';

mixin HttpInitMixin on ListenMixin {
  late HttpClient client;
  String get unixSocketPath;
  @override
  void initStateListen(add) {
    super.initStateListen(add);
    // client = HttpClient()..findProxy = _findProxy;
    client = createUnixSocketClient(unixSocketPath);
  }

  // String _findProxy(Uri uri) {
  //   return HttpClient.findProxyFromEnvironment(
  //     uri,
  //     environment: {'http_proxy': proxyPort, 'https_proxy': proxyPort},
  //   );
  // }
}
