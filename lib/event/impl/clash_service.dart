import 'dart:io';

import 'package:clash_service/clash_service.dart';
import 'package:dio/dio.dart';
import 'package:nop/nop.dart';

import 'dio/unix_socket_dio.dart';

abstract final class _Apis {
  static const clashEnv = 'baseInfo/env';
  static const clashStart = 'clash';
}

abstract final class ClashServiceApi {
  static final _dio = Dio(
    .new(
      baseUrl: 'http://localhost:7887/',
      contentType: Headers.jsonContentType,
    ),
  )..interceptors.add(_RetryInterceptor());

  static Future<ApiResp> getClashEnv() async {
    final res = await _dio.get(_Apis.clashEnv);
    return .transform(res.data);
  }

  static Future<ApiResp> startClash(ClashStartReq req) async {
    final res = await _dio.post(_Apis.clashStart, data: req.toJson());

    return .transform(res.data);
  }
}

class _RetryInterceptor extends Interceptor {
  static final _implDio = Dio(
    .new(
      baseUrl: 'http://localhost:7887/',
      contentType: Headers.jsonContentType,
    ),
  )..httpClientAdapter = UnixSocketAdapter(clashSocket, port: 0);

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    Object? error;
    var count = 3;

    while (count > 0) {
      count -= 1;
      try {
        final res = await _implDio.fetch(options);
        handler.resolve(res);
        return;
      } catch (e) {
        error = e;

        if (e case DioException(
          error: SocketException(
            osError: OSError(message: var message, errorCode: var errorCode),
          ),
        )) {
          Log.e('error: $message, code: $errorCode');
          if (errorCode != 61) {
            break;
          }

          await Future.delayed(const Duration(seconds: 2));
        }
      }
    }

    if (error case DioException e) {
      handler.reject(e);
    } else {
      handler.reject(DioException(requestOptions: options, error: error));
    }
  }
}
