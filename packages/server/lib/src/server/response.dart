import 'dart:convert';

/// 控制 API 的响应信封：`{"code":0,"msg":"","data":...}`。
///
/// 服务端（Go）与客户端（`packages/clash_service`）共用这一形状。
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

  factory transform(
    Map<String, dynamic> map, [
    D Function(dynamic data)? fromJson,
  ]) {
    final code = map["code"] ?? -1;
    final msg = map["msg"] ?? '';
    final data = map["data"];
    final res = ApiResp<D>._(code: code, msg: msg, data: data);
    if (res.success) {
      if (fromJson == null) {
        if (data is D || D == dynamic) {
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
