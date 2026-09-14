import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'unix_socket_http.dart';

class UnixSocketAdapter implements HttpClientAdapter {
  final String socketPath;
  late final HttpClient _client;
  var _closed = false;

  UnixSocketAdapter(this.socketPath) {
    _client = createUnixSocketClient(socketPath);
  }

  @override
  void close({bool force = false}) {
    _closed = true;
    _client.close(force: force);
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (_closed) {
      throw StateError(
        "Can't establish connection after the adapter was closed.",
      );
    }
    return _fetch(options, requestStream, cancelFuture);
  }

  Future<ResponseBody> _fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final httpClient = _client;
    final reqFuture = httpClient.openUrl(options.method, options.uri);
    late HttpClientRequest request;
    try {
      final connectionTimeout = options.connectTimeout;
      if (connectionTimeout != null && connectionTimeout > Duration.zero) {
        request = await reqFuture.timeout(
          connectionTimeout,
          onTimeout: () {
            throw DioException.connectionTimeout(
              requestOptions: options,
              timeout: connectionTimeout,
            );
          },
        );
      } else {
        request = await reqFuture;
      }

      final requestWR = WeakReference<HttpClientRequest>(request);
      cancelFuture?.whenComplete(() {
        requestWR.target?.abort();
      });

      // Set Headers
      options.headers.forEach((key, value) {
        if (value != null) {
          request.headers.set(
            key,
            value,
            preserveHeaderCase: options.preserveHeaderCase,
          );
        }
      });
    } on SocketException catch (e) {
      if (e.message.contains('timed out')) {
        final Duration effectiveTimeout;
        if (options.connectTimeout != null &&
            options.connectTimeout! > Duration.zero) {
          effectiveTimeout = options.connectTimeout!;
        } else if (httpClient.connectionTimeout != null &&
            httpClient.connectionTimeout! > Duration.zero) {
          effectiveTimeout = httpClient.connectionTimeout!;
        } else {
          effectiveTimeout = Duration.zero;
        }
        throw DioException.connectionTimeout(
          requestOptions: options,
          timeout: effectiveTimeout,
          error: e,
        );
      }
      throw DioException.connectionError(
        requestOptions: options,
        reason: e.message,
        error: e,
      );
    }

    request.followRedirects = options.followRedirects;
    request.maxRedirects = options.maxRedirects;
    request.persistentConnection = options.persistentConnection;

    if (requestStream != null) {
      // Transform the request data.
      Future<dynamic> future = request.addStream(requestStream);
      final sendTimeout = options.sendTimeout;
      if (sendTimeout != null && sendTimeout > Duration.zero) {
        future = future.timeout(
          sendTimeout,
          onTimeout: () {
            request.abort();
            throw DioException.sendTimeout(
              timeout: sendTimeout,
              requestOptions: options,
            );
          },
        );
      }
      await future;
    }

    Future<HttpClientResponse> future = request.close();
    final receiveTimeout = options.receiveTimeout ?? Duration.zero;
    if (receiveTimeout > Duration.zero) {
      future = future.timeout(
        receiveTimeout,
        onTimeout: () {
          request.abort();
          throw DioException.receiveTimeout(
            timeout: receiveTimeout,
            requestOptions: options,
          );
        },
      );
    }
    late final HttpClientResponse responseStream;
    try {
      responseStream = await future;
    } on HttpException catch (e, s) {
      if (e.message.contains(
        'Connection closed before full header was received',
      )) {
        throw DioException.connectionError(
          requestOptions: options,
          reason: e.message,
          error: e,
          stackTrace: s,
        );
      }
      rethrow;
    }

    // if (validateCertificate != null) {
    //   final host = options.uri.host;
    //   final port = options.uri.port;
    //   final bool isCertApproved = validateCertificate!(
    //     responseStream.certificate,
    //     host,
    //     port,
    //   );
    //   if (!isCertApproved) {
    //     throw DioException.badCertificate(
    //       requestOptions: options,
    //       error: responseStream.certificate,
    //     );
    //   }
    // }

    final headers = <String, List<String>>{};
    responseStream.headers.forEach((key, values) {
      headers[key] = values;
    });

    // Extract HTTP protocol version from the response headers.
    // The protocolVersion is available in the internal `_HttpHeaders`
    // implementation but not exposed in the public `HttpHeaders` interface,
    // so we use dynamic access. This may fail in certain environments
    // (e.g., tests with mocks), so we catch and omit errors.
    String? httpVersion;
    try {
      httpVersion = (responseStream.headers as dynamic).protocolVersion;
    } catch (_) {}

    final responseBody = ResponseBody(
      responseStream.cast(),
      responseStream.statusCode,
      headers: headers,
      isRedirect:
          responseStream.isRedirect || responseStream.redirects.isNotEmpty,
      redirects: responseStream.redirects
          .map((e) => RedirectRecord(e.statusCode, e.method, e.location))
          .toList(),
      statusMessage: responseStream.reasonPhrase,
    );
    if (httpVersion != null) {
      responseBody.extra[HttpClientAdapter.extraKeyHttpVersion] ??= httpVersion;
    }
    return responseBody;
  }
}
