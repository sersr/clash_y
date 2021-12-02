import 'package:dio/dio.dart';
import 'package:nop_db/isolate_event.dart';
import 'dart:io';

mixin DioInitMixin on ListenMixin {
  late Dio dio;
  late HttpClient client;
  String get externalUi;
  String get proxyPort;
  @override
  void initStateListen(add) {
    super.initStateListen(add);
    client = HttpClient()..findProxy = _findProxy;
    dio = Dio(BaseOptions(baseUrl: externalUi));
  }

  String _findProxy(Uri uri) {
    return HttpClient.findProxyFromEnvironment(uri,
        environment: {'http_proxy': proxyPort, 'https_proxy': proxyPort});
  }
}
