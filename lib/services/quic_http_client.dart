import 'dart:async';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:reader/services/debug_trace.dart';
import 'package:reader/utils/platform_capabilities.dart';

class AppHttpClientFactory {
  AppHttpClientFactory._();

  static http.Client create() {
    if (PlatformCapabilities.supportsCronetHttp) {
      return QuicHttpClient();
    }
    return http.Client();
  }
}

class QuicHttpClient extends http.BaseClient {
  QuicHttpClient({http.Client? fallbackClient})
    : _fallbackClient = fallbackClient ?? http.Client();

  static const MethodChannel _channel = MethodChannel('easy_copy/quic_http');

  final http.Client _fallbackClient;
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed) {
      throw http.ClientException('HTTP client has been closed.', request.url);
    }

    final Uint8List body = await request.finalize().toBytes();
    try {
      final Object? rawResponse = await _channel
          .invokeMethod<Object?>('request', <String, Object?>{
            'url': request.url.toString(),
            'method': request.method,
            'headers': request.headers,
            'body': body,
            'followRedirects': request.followRedirects,
            'maxRedirects': request.maxRedirects,
          });
      return _buildResponse(request, rawResponse);
    } on MissingPluginException {
      return _sendWithFallback(request, body);
    } on PlatformException catch (error) {
      throw http.ClientException(
        error.message?.trim().isNotEmpty == true ? error.message! : error.code,
        request.url,
      );
    }
  }

  @override
  void close() {
    _closed = true;
    _fallbackClient.close();
    super.close();
  }

  http.StreamedResponse _buildResponse(
    http.BaseRequest request,
    Object? rawResponse,
  ) {
    if (rawResponse is! Map<Object?, Object?>) {
      throw http.ClientException('Invalid Cronet response.', request.url);
    }
    final int statusCode = (rawResponse['statusCode'] as num?)?.toInt() ?? 0;
    final Uint8List body = rawResponse['body'] as Uint8List? ?? Uint8List(0);
    final Map<String, String> headers =
        (rawResponse['headers'] as Map<Object?, Object?>? ?? const {}).map(
          (Object? key, Object? value) =>
              MapEntry(key.toString().toLowerCase(), value?.toString() ?? ''),
        );
    final String protocol = (rawResponse['protocol'] as String? ?? '').trim();
    final String url = (rawResponse['url'] as String? ?? '').trim();
    if (protocol.isNotEmpty &&
        (protocol.toLowerCase().contains('h3') ||
            protocol.toLowerCase().contains('quic'))) {
      DebugTrace.log('net.cronet_http3', <String, Object?>{
        'uri': '${request.url.scheme}://${request.url.host}${request.url.path}',
        'protocol': protocol,
        if (url.isNotEmpty) 'url': url,
      });
    }

    return http.StreamedResponse(
      Stream<List<int>>.value(body),
      statusCode,
      contentLength: body.length,
      request: request,
      headers: headers,
      reasonPhrase: rawResponse['reasonPhrase'] as String?,
      isRedirect: statusCode >= 300 && statusCode < 400,
    );
  }

  Future<http.StreamedResponse> _sendWithFallback(
    http.BaseRequest source,
    Uint8List body,
  ) async {
    final http.StreamedRequest fallbackRequest =
        http.StreamedRequest(source.method, source.url)
          ..headers.addAll(source.headers)
          ..followRedirects = source.followRedirects
          ..maxRedirects = source.maxRedirects
          ..persistentConnection = source.persistentConnection
          ..contentLength = body.length;
    fallbackRequest.sink.add(body);
    await fallbackRequest.sink.close();
    return _fallbackClient.send(fallbackRequest);
  }
}
