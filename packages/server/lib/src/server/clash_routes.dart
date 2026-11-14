import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:nop/nop.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart' as web;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../my_router.dart';
import 'clash_process.dart';
import 'models/models.dart';
import 'response.dart';

extension on Request {
  dynamic get data => context['clashy_data'];
}

abstract final class ClashRoutes {
  static final _sockets = <WebSocketChannel>[];
  static final _sockets2 = <StreamSink<List<int>>>[];
  static Timer? _timer;

  static Handler get handler {
    final router = MyRouter();
    router
      ..ws('/ws', web.webSocketHandler(ws))
      ..get('/', getClash)
      ..get('/status', getStatus)
      ..post('/', startClash)
      ..post('/core', startCoreClash)
      ..get('/vpn/status', getVpnStatus)
      ..post('/vpn/start', startVpn)
      ..post('/vpn/stop', stopVpn)
      ..post('/reload', reloadClashConfig)
      ..post('/profile', updateProfile)
      ..post('/stop', stopClash);

    return router.call;
  }

  static Future<Resp> ws(
    WebSocketChannel webSocket,
    String? subprotocol,
  ) async {
    _sockets.add(webSocket);
    webSocket.stream.listen(
      (data) {
        print(data);
      },
      cancelOnError: true,
      onDone: () => _sockets.remove(webSocket),
      onError: (_) => _sockets.remove(webSocket),
    );
    _start();
    return .ok();
  }

  static void _start() {
    _timer?.cancel();
    Log.w('sockets: ${_sockets.length}');
    if (_sockets.isEmpty && _sockets2.isEmpty) return;
    for (var socket in _sockets) {
      socket.sink.add("value: ${Random().nextInt(1024)}");
    }
    for (var socket in _sockets2) {
      socket.add(utf8.encode("value: ${Random().nextInt(1024)}"));
    }
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 1), _start);
  }

  static Future<Resp> getClash(Request request) async => .ok(
    jsonEncode({
      'dir': Platform.resolvedExecutable,
      'work': Directory.current.path,
    }),
  );

  static Future<Resp> getStatus(Request request) async =>
      .ok(ClashProcess.started);

  static Future<Resp> getVpnStatus(Request request) async =>
      .ok(ClashProcess.vpnEnabled);

  static Future<Resp> startClash(Request request) =>
      _startProfile(request, vpnEnabled: true);

  static Future<Resp> startCoreClash(Request request) =>
      _startProfile(request, vpnEnabled: false);

  static Future<Resp> startVpn(Request request) =>
      _startProfile(request, vpnEnabled: true);

  static Future<Resp> _startProfile(
    Request request, {
    required bool vpnEnabled,
  }) async {
    final profile = ClashProfile.tryParse(request.data);
    if (profile == null || profile.configDir.isEmpty) {
      return .error(data: 'invalid profile');
    }

    final result = vpnEnabled
        ? await ClashProcess.run(profile.configDir)
        : await ClashProcess.runCoreOnly(profile.configDir);
    if (result case String error when error.isNotEmpty) {
      return .error(data: error);
    }
    await ClashProcess.setProfile(profile);
    return .ok(result);
  }

  static Future<Resp> updateProfile(Request request) async {
    final profile = ClashProfile.tryParse(request.data);
    if (profile == null) return .error(data: 'invalid profile');

    await ClashProcess.updateProfile(profile);
    return .ok();
  }

  static Future<Resp> stopVpn(Request request) async {
    final error = await ClashProcess.stopVpn();
    if (error != null) return .error(data: error);
    return .ok();
  }

  static Future<Resp> reloadClashConfig(Request request) async {
    final error = await ClashProcess.reloadConfig();
    if (error != null) return .error(data: error);
    return .ok();
  }

  static Future<Resp> stopClash(Request request) async {
    final error = await ClashProcess.stop();
    if (error != null && error.isNotEmpty) return .error(data: error);
    return .ok();
  }
}
