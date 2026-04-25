import 'dart:async';
import 'dart:collection';

import 'package:easy_copy/config/app_config.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class EasyCopyImageCaches {
  EasyCopyImageCaches._();

  static const int _readerPrefetchLimit = 8;
  static const int _readerPrefetchConcurrency = 2;

  static final CacheManager coverCache = CacheManager(
    Config(
      'easy_copy_cover',
      stalePeriod: const Duration(days: 14),
      maxNrOfCacheObjects: 400,
    ),
  );

  static final CacheManager readerCache = CacheManager(
    Config(
      'easy_copy_reader',
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 1600,
    ),
  );

  static final Queue<_ReaderPrefetchRequest> _readerPrefetchQueue =
      Queue<_ReaderPrefetchRequest>();
  static final Set<String> _queuedReaderPrefetchUrls = <String>{};
  static int _activeReaderPrefetches = 0;

  static Future<void> prefetchReaderImages(
    Iterable<String> urls, {
    String referer = '',
  }) async {
    for (final String url in urls.take(_readerPrefetchLimit)) {
      final String normalizedUrl = url.trim();
      if (normalizedUrl.isEmpty ||
          !_queuedReaderPrefetchUrls.add(normalizedUrl)) {
        continue;
      }
      _readerPrefetchQueue.add(
        _ReaderPrefetchRequest(url: normalizedUrl, referer: referer),
      );
    }
    _drainReaderPrefetchQueue();
  }

  static void _drainReaderPrefetchQueue() {
    while (_activeReaderPrefetches < _readerPrefetchConcurrency &&
        _readerPrefetchQueue.isNotEmpty) {
      final _ReaderPrefetchRequest request = _readerPrefetchQueue.removeFirst();
      _activeReaderPrefetches += 1;
      unawaited(_runReaderPrefetch(request));
    }
  }

  static Future<void> _runReaderPrefetch(_ReaderPrefetchRequest request) async {
    try {
      await readerCache.downloadFile(
        request.url,
        authHeaders: readerImageHeaders(request.referer),
      );
    } catch (_) {
      return;
    } finally {
      _queuedReaderPrefetchUrls.remove(request.url);
      _activeReaderPrefetches -= 1;
      _drainReaderPrefetchQueue();
    }
  }

  static Map<String, String> readerImageHeaders(String referer) {
    return <String, String>{
      'User-Agent': AppConfig.desktopUserAgent,
      'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
      if (referer.trim().isNotEmpty) 'Referer': referer.trim(),
    };
  }
}

class _ReaderPrefetchRequest {
  const _ReaderPrefetchRequest({required this.url, required this.referer});

  final String url;
  final String referer;
}
