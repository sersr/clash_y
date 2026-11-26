import 'dart:io';

import 'package:dio/dio.dart';
import 'package:nop/nop.dart';
import 'package:server/server.dart' show ApiResp, ClashProfile, clashSocket;

import '../api/dio/unix_socket_dio.dart';

abstract final class _Apis {
  static const serviceVersion = 'version';
  static const clashStartCore = 'clash/core';
  static const clashVpnStart = 'clash/vpn/start';
  static const clashVpnStop = 'clash/vpn/stop';
  static const clashVpnStatus = 'clash/vpn/status';
  static const clashReload = 'clash/reload';
  static const clashProfile = 'clash/profile';
  static const clashStatus = 'clash/status';
}

abstract final class ClashServiceApi {
  /// Socket the client talks to. The desktop daemon by default; the mobile
  /// tunnel sets it once during app start, before the first request.
  static String socketPath = clashSocket;

  static final _dio = Dio(
    .new(baseUrl: 'http://localhost/', contentType: Headers.jsonContentType),
  )..interceptors.add(_RetryInterceptor());
  static Future<String?> getServiceVersion() async {
    try {
      final res = await _dio.get(_Apis.serviceVersion);
      if (res.data case Map<String, dynamic> body) {
        final response = ApiResp<String>.transform(body);
        final serviceVersion = response.autoData();
        if (response.success && serviceVersion != null) {
          return serviceVersion;
        }
      }
      Log.e('Invalid clashyService version response: ${res.data}');
    } on DioException catch (error) {
      Log.e('Failed to read clashyService version: $error');
    }
    return null;
  }

  /// One non-retrying probe of the control API: Android starts its service
  /// asynchronously, so callers poll this instead of waiting on retries.
  static Future<bool> isReady() async {
    try {
      final res = await _RetryInterceptor._implDio.get<Object?>(
        _Apis.serviceVersion,
      );
      return res.data is Map;
    } catch (_) {
      return false;
    }
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

  /// Hands [profile] to the running service. Unless [refresh] is false it
  /// also refreshes the subscription; with `refresh: false` only the schedule
  /// is stored, which is what the app wants right after writing config.yaml.
  static Future<ApiResp?> updateProfile(
    ClashProfile profile, {
    bool refresh = true,
  }) async {
    try {
      final res = await _dio.post(
        _Apis.clashProfile,
        data: profile.toJson(),
        queryParameters: refresh ? null : {'refresh': 'false'},
      );
      return ApiResp.transform(res.data);
    } catch (e) {
      Log.d('profile API unavailable: $e');
      return null;
    }
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
  /// Built on the first request, so it picks up the socket the app resolved
  /// during start-up.
  static Dio? _client;

  static Dio get _implDio => _client ??= Dio(
    .new(baseUrl: 'http://localhost/', contentType: Headers.jsonContentType),
  )..httpClientAdapter = UnixSocketAdapter(ClashServiceApi.socketPath);

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
        if (!_isServiceStartingError(e)) break;
        Log.w('clashyService is not ready yet: $e');
        if (count > 0) {
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
    }

    if (error case DioException e) {
      handler.reject(e);
    } else {
      handler.reject(DioException(requestOptions: options, error: error));
    }
  }

  /// 服务刚启动时连接会被拒绝，或 Windows 命名管道尚未创建/繁忙。
  ///
  /// 此时短暂等待后重试；其他错误立即失败。
  static bool _isServiceStartingError(Object error) {
    final cause = error is DioException ? error.error : error;
    if (cause is SocketException) {
      final code = cause.osError?.errorCode;
      return code == 2 || // ENOENT
          code == 61 || // ECONNREFUSED (macOS/BSD)
          code == 111 || // ECONNREFUSED (Linux)
          code == 10061; // WSAECONNREFUSED (Windows)
    }
    // dart_ipc 的 Windows 命名管道错误实现 IOException（例如管道尚未创建）。
    return cause is IOException;
  }
}
