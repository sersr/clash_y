import 'dart:io';

import 'package:clash_service/clash_service.dart';
import 'package:common/common.dart';
import 'package:dio/dio.dart';
import 'package:nop/nop.dart';

import 'dio/unix_socket_dio.dart';

abstract final class _Apis {
  static const clashEnv = 'baseInfo/env';
  static const clashStart = 'clash';
  static const clashStartCore = 'clash/core';
  static const clashVpnStart = 'clash/vpn/start';
  static const clashVpnStop = 'clash/vpn/stop';
  static const clashVpnStatus = 'clash/vpn/status';
  static const clashReload = 'clash/reload';
  static const clashProfile = 'clash/profile';
  static const clashStop = 'clash/stop';
  static const clashStatus = 'clash/status';
}

abstract final class ClashServiceApi {
  static final _dio = Dio(
    .new(baseUrl: 'http://localhost/', contentType: Headers.jsonContentType),
  )..interceptors.add(_RetryInterceptor());

  static Future<ApiResp> getClashEnv() async {
    final res = await _dio.get(_Apis.clashEnv);
    return .transform(res.data);
  }

  static Future<ApiResp> startClash(ClashProfile profile) async {
    final res = await _dio.post(_Apis.clashStart, data: profile.toJson());

    return .transform(res.data);
  }

  static Future<ApiResp> startClashCore(ClashProfile profile) async {
    final res = await _dio.post(_Apis.clashStartCore, data: profile.toJson());

    return .transform(res.data);
  }

  static Future<ApiResp> startVpn(ClashProfile profile) async {
    final res = await _dio.post(_Apis.clashVpnStart, data: profile.toJson());

    return .transform(res.data);
  }

  static Future<ApiResp> stopVpn() async {
    final res = await _dio.post(_Apis.clashVpnStop);

    return .transform(res.data);
  }

  static Future<ApiResp> reloadClashConfig() async {
    final res = await _dio.post(_Apis.clashReload);

    return .transform(res.data);
  }

  /// Switches the profile a running service refreshes itself from.
  static Future<ApiResp> updateClashProfile(ClashProfile profile) async {
    final res = await _dio.post(_Apis.clashProfile, data: profile.toJson());

    return .transform(res.data);
  }

  static Future<ApiResp> stopClash() async {
    final res = await _dio.post(_Apis.clashStop);

    return .transform(res.data);
  }

  static Future<bool> isClashRunning() async {
    final res = await _dio.get(_Apis.clashStatus);
    final response = ApiResp.transform(res.data);
    return response.success && response.data == true;
  }

  static Future<bool> isVpnActive() async {
    final res = await _dio.get(_Apis.clashVpnStatus);
    final response = ApiResp.transform(res.data);
    return response.success && response.data == true;
  }
}

class _RetryInterceptor extends Interceptor {
  static final _implDio = Dio(
    .new(baseUrl: 'http://localhost/', contentType: Headers.jsonContentType),
  )..httpClientAdapter = UnixSocketAdapter(clashSocket);

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

extension ProfileServiceX on Profile {
  /// Builds the service payload for this profile.
  ClashProfile toClashProfile(String configDir) {
    return ClashProfile(
      configDir: configDir,
      id: id,
      name: showName,
      url: url,
      updateInterval: updateInterval,
      updateTime: updateTime,
    );
  }
}
