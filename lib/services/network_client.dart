import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:reader/services/debug_trace.dart';

class NetworkResponseBytes {
  const NetworkResponseBytes({
    required this.statusCode,
    required this.headers,
    required this.bytes,
  });

  final int statusCode;
  final Map<String, String> headers;
  final List<int> bytes;
}

class NetworkClient {
  NetworkClient._();

  static const Duration apiTimeout = Duration(seconds: 10);
  static const Duration htmlTimeout = Duration(seconds: 12);
  static const Duration imageTimeout = Duration(seconds: 18);
  static const Duration _retryDelay = Duration(milliseconds: 320);
  static const Duration _slowRequestThreshold = Duration(milliseconds: 2500);

  static Future<http.Response> get(
    http.Client client,
    Uri uri, {
    Map<String, String>? headers,
    Duration timeout = apiTimeout,
    int maxRetries = 1,
    String label = 'get',
  }) {
    return _withRetry<http.Response>(
      label: label,
      uri: uri,
      maxRetries: maxRetries,
      operation: () =>
          _send(client, 'GET', uri, headers: headers, timeout: timeout),
      shouldRetryResult: (http.Response response) =>
          _isRetryableStatus(response.statusCode),
      statusCodeForResult: (http.Response response) => response.statusCode,
    );
  }

  static Future<http.Response> post(
    http.Client client,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Duration timeout = apiTimeout,
    int maxRetries = 0,
    String label = 'post',
  }) {
    return _withRetry<http.Response>(
      label: label,
      uri: uri,
      maxRetries: maxRetries,
      operation: () => _send(
        client,
        'POST',
        uri,
        headers: headers,
        body: body,
        timeout: timeout,
      ),
      shouldRetryResult: (http.Response response) =>
          _isRetryableStatus(response.statusCode),
      statusCodeForResult: (http.Response response) => response.statusCode,
    );
  }

  static Future<NetworkResponseBytes> sendForBytes(
    http.Client client,
    Uri uri, {
    required Map<String, String> headers,
    Duration timeout = htmlTimeout,
    int maxRetries = 1,
    String label = 'send',
  }) async {
    final response = await _withRetry<http.Response>(
      label: label,
      uri: uri,
      maxRetries: maxRetries,
      operation: () => _send(
        client,
        'GET',
        uri,
        headers: headers,
        timeout: timeout,
        followRedirects: false,
      ),
      shouldRetryResult: (response) => _isRetryableStatus(response.statusCode),
      statusCodeForResult: (response) => response.statusCode,
    );
    return NetworkResponseBytes(
      statusCode: response.statusCode,
      headers: response.headers,
      bytes: response.bodyBytes,
    );
  }

  static Future<http.Response> _send(
    http.Client client,
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    required Duration timeout,
    bool followRedirects = true,
  }) {
    final abort = Completer<void>();
    final request = http.AbortableRequest(
      method,
      uri,
      abortTrigger: abort.future,
    )..followRedirects = followRedirects;
    if (headers != null) request.headers.addAll(headers);
    if (body is String) {
      request.body = body;
    } else if (body is List<int>) {
      request.bodyBytes = body;
    } else if (body is Map) {
      request.bodyFields = body.cast<String, String>();
    } else if (body != null) {
      throw ArgumentError.value(body, 'body');
    }
    return client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(
          timeout,
          onTimeout: () {
            abort.complete();
            throw TimeoutException('Request timed out: $uri', timeout);
          },
        );
  }

  static Future<T> _withRetry<T>({
    required String label,
    required Uri uri,
    required int maxRetries,
    required Future<T> Function() operation,
    required bool Function(T result) shouldRetryResult,
    required int Function(T result) statusCodeForResult,
  }) async {
    final int allowedRetries = maxRetries < 0 ? 0 : maxRetries;
    Object? lastError;
    StackTrace? lastStackTrace;

    for (int attempt = 0; attempt <= allowedRetries; attempt += 1) {
      final Stopwatch stopwatch = Stopwatch()..start();
      try {
        final T result = await operation();
        stopwatch.stop();
        final int statusCode = statusCodeForResult(result);
        _logSlowRequest(
          label: label,
          uri: uri,
          elapsedMs: stopwatch.elapsedMilliseconds,
          statusCode: statusCode,
          attempt: attempt,
        );
        if (attempt < allowedRetries && shouldRetryResult(result)) {
          await _delayBeforeRetry(attempt);
          continue;
        }
        return result;
      } catch (error, stackTrace) {
        stopwatch.stop();
        lastError = error;
        lastStackTrace = stackTrace;
        _logSlowRequest(
          label: label,
          uri: uri,
          elapsedMs: stopwatch.elapsedMilliseconds,
          statusCode: null,
          attempt: attempt,
          error: error,
        );
        if (attempt >= allowedRetries || !_isRetryableError(error)) {
          Error.throwWithStackTrace(error, stackTrace);
        }
        await _delayBeforeRetry(attempt);
      }
    }

    Error.throwWithStackTrace(lastError!, lastStackTrace!);
  }

  static bool _isRetryableStatus(int statusCode) {
    return statusCode == 408 ||
        statusCode == 429 ||
        statusCode == 500 ||
        statusCode == 502 ||
        statusCode == 503 ||
        statusCode == 504;
  }

  static bool _isRetryableError(Object error) {
    return error is TimeoutException ||
        error is SocketException ||
        error is HandshakeException ||
        error is http.ClientException;
  }

  static Future<void> _delayBeforeRetry(int attempt) {
    return Future<void>.delayed(
      Duration(milliseconds: _retryDelay.inMilliseconds * (attempt + 1)),
    );
  }

  static void _logSlowRequest({
    required String label,
    required Uri uri,
    required int elapsedMs,
    required int? statusCode,
    required int attempt,
    Object? error,
  }) {
    if (elapsedMs < _slowRequestThreshold.inMilliseconds && error == null) {
      return;
    }
    DebugTrace.log('net.request', <String, Object?>{
      'label': label,
      'uri': '${uri.scheme}://${uri.host}${uri.path}',
      'statusCode': statusCode,
      'elapsedMs': elapsedMs,
      'attempt': attempt + 1,
      if (error != null) 'error': error.toString(),
    });
  }
}
