import 'dart:async';

import 'package:easy_copy/config/app_config.dart';
import 'package:easy_copy/services/debug_trace.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:http/http.dart' as http;

class NetworkDiagnostics {
  NetworkDiagnostics._();

  static const Duration _timeout = Duration(seconds: 10);

  static Future<void> probeImage(
    String url, {
    required String referer,
    String label = 'image.probe',
  }) async {
    if (!kDebugMode || !AppConfig.debugProbeImages) {
      return;
    }
    final String normalizedUrl = url.trim();
    if (normalizedUrl.isEmpty) {
      return;
    }
    final Uri? uri = Uri.tryParse(normalizedUrl);
    if (uri == null || !uri.hasScheme) {
      return;
    }

    final Stopwatch stopwatch = Stopwatch()..start();
    try {
      final http.Response response = await http
          .get(
            uri,
            headers: <String, String>{
              'Range': 'bytes=0-31',
              'User-Agent': AppConfig.desktopUserAgent,
              if (referer.trim().isNotEmpty) 'Referer': referer.trim(),
              'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
            },
          )
          .timeout(_timeout);
      stopwatch.stop();

      final String headBytes = response.bodyBytes
          .take(16)
          .map((int value) => value.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      DebugTrace.log('net.$label', <String, Object?>{
        'url': normalizedUrl,
        'host': uri.host,
        'status': response.statusCode,
        'elapsedMs': stopwatch.elapsedMilliseconds,
        'contentType': response.headers['content-type'] ?? '',
        'contentLength': response.headers['content-length'] ?? '',
        'byteCount': response.bodyBytes.length,
        'head': headBytes,
      });
    } catch (error) {
      stopwatch.stop();
      DebugTrace.log('net.${label}_error', <String, Object?>{
        'url': normalizedUrl,
        'host': uri.host,
        'elapsedMs': stopwatch.elapsedMilliseconds,
        'error': error.toString(),
      });
    }
  }

  static Future<void> probeImageVariants(
    String url, {
    required String referer,
    String label = 'image.probe',
  }) async {
    if (!kDebugMode || !AppConfig.debugProbeImages) {
      return;
    }
    unawaited(
      probeImage(url, referer: '', label: '${label}_no_referer'),
    );
    unawaited(
      probeImage(url, referer: referer, label: '${label}_with_referer'),
    );
  }
}
