import 'dart:io';

import 'package:dio/dio.dart';

HttpClient createUnixSocketClient(String sock) {
  final client = HttpClient();
  HttpClientAdapter;
  client.connectionFactory = (uri, proxyHost, proxyPort) {
    final address = InternetAddress(sock, type: InternetAddressType.unix);
    return Socket.startConnect(address, 0);
  };
  client.findProxy = (uri) => 'DIRECT';

  return client;
}

Future<Socket> createUnixSocket(String sock) async {
  final address = InternetAddress(sock, type: InternetAddressType.unix);
  return Socket.connect(address, 0);
}
