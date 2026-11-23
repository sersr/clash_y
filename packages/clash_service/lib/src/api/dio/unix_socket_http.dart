import 'dart:async';
import 'dart:io';

import 'package:dart_ipc/dart_ipc.dart' show connect;

HttpClient createUnixSocketClient(String sock) {
  final client = HttpClient();
  client.connectionFactory = (uri, proxyHost, proxyPort) async {
    final future = connect(sock);
    final socket = await future;
    return ConnectionTask.fromSocket(future, socket.destroy);
  };
  client.findProxy = (uri) => 'DIRECT';

  return client;
}

Future<Socket> createUnixSocket(String sock) async {
  final address = InternetAddress(sock, type: InternetAddressType.unix);
  return Socket.connect(address, 0);
}
