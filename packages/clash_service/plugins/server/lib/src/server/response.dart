import 'dart:convert';

import 'package:shelf/shelf.dart';

Map<String, String> get jsonHeader => {'content-type': 'application/json'};

final class Resp extends Response {
  new res(
    ApiResp resp, {
    super.headers = const {'content-type': 'application/json'},
    super.encoding,
    super.context,
  }) : super.ok(resp.toString());
}

class ApiResp<D> {
  int code;
  String msg;
  dynamic data;

  ApiResp._({required this.code, required this.msg, this.data});

  ApiResp.ok([this.data]) : code = 0, msg = '';
  ApiResp.error({this.code = 1001, required this.msg, this.data});

  D? _data;

  D? autoData() {
    if (_data is D) return _data;
    if (D == dynamic) return data;
    return null;
  }

  static ApiResp<T> transform<T>(
    Map<String, dynamic> map, [

    T Function(dynamic data)? fromJson,
  ]) {
    final code = map["code"] ?? -1;
    final msg = map["msg"] ?? '';
    final data = map["data"];
    final res = ApiResp<T>._(code: code, msg: msg, data: data);
    if (res.success) {
      if (fromJson == null) {
        if (data is T || T == dynamic) {
          res._data = data;
        }
      } else {
        res._data = fromJson(data);
      }
    }
    return res;
  }

  bool get success => code == 0;

  Map<String, dynamic> toJson() {
    return {"code": code, "msg": msg, "data": data};
  }

  @override
  String toString() {
    return jsonEncode(toJson());
  }
}
