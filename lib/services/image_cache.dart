import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:reader/config/app_config.dart';

const int readerPrefetchLimit = 10;
const int readerPriorityPrefetchLimit = 2;
const int readerPrefetchConcurrency = 5;

/// An ordered index for one chapter, including mixed local and remote images.
class ReaderPrefetchIndex {
  ReaderPrefetchIndex(List<String> urls) {
    for (int i = 0; i < urls.length; i++) {
      final url = urls[i].trim();
      final scheme = Uri.tryParse(url)?.scheme;
      if (scheme == 'http' || scheme == 'https') _remote.add((i, url));
    }
  }

  final List<(int, String)> _remote = [];
  bool get isEmpty => _remote.isEmpty;

  List<String> after(int currentIndex) {
    int low = 0;
    int high = _remote.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (_remote[mid].$1 <= currentIndex) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    final selected = <String>{};
    for (
      int i = low;
      i < _remote.length && selected.length < readerPrefetchLimit;
      i++
    ) {
      selected.add(_remote[i].$2);
    }
    return selected.toList(growable: false);
  }
}

class AppImageCaches {
  AppImageCaches._();

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

  /// Uses the original URL key only; this never fetches or selects a thumbnail.
  static Future<Uint8List?> readReaderOriginalBytes(String url) async {
    try {
      final FileInfo? cached = await readerCache.getFileFromCache(url);
      return cached == null ? null : await cached.file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  static final Queue<_ReaderPrefetchRequest> _priorityReaderPrefetchQueue =
      Queue<_ReaderPrefetchRequest>();
  static final Queue<_ReaderPrefetchRequest> _normalReaderPrefetchQueue =
      Queue<_ReaderPrefetchRequest>();
  static final Set<String> _queuedReaderPrefetchUrls = <String>{};
  static final Set<String> _activeReaderPrefetchUrls = <String>{};
  static final Set<String> _priorityReaderPrefetchUrls = <String>{};
  static int _activeReaderPrefetches = 0;

  static void replaceReaderPrefetchWindow(
    Iterable<String> urls, {
    String referer = '',
  }) {
    _clearPendingReaderPrefetches();
    final List<String> windowUrls = <String>[];
    final Set<String> seen = <String>{};
    for (final String url in urls) {
      if (windowUrls.length >= readerPrefetchLimit) {
        break;
      }
      final String normalizedUrl = url.trim();
      if (normalizedUrl.isEmpty || !seen.add(normalizedUrl)) {
        continue;
      }
      windowUrls.add(normalizedUrl);
    }

    _priorityReaderPrefetchUrls
      ..clear()
      ..addAll(windowUrls.take(readerPriorityPrefetchLimit));
    for (int index = 0; index < windowUrls.length; index++) {
      final String normalizedUrl = windowUrls[index];
      if (!_queuedReaderPrefetchUrls.add(normalizedUrl)) {
        continue;
      }
      final bool priority = index < readerPriorityPrefetchLimit;
      final _ReaderPrefetchRequest request = _ReaderPrefetchRequest(
        url: normalizedUrl,
        referer: referer,
      );
      if (priority) {
        _priorityReaderPrefetchQueue.add(request);
      } else {
        _normalReaderPrefetchQueue.add(request);
      }
    }
    _drainReaderPrefetchQueue();
  }

  static void clearReaderPrefetchWindow() {
    _clearPendingReaderPrefetches();
    _priorityReaderPrefetchUrls.clear();
  }

  static void _clearPendingReaderPrefetches() {
    _clearReaderPrefetchQueue(_priorityReaderPrefetchQueue);
    _clearReaderPrefetchQueue(_normalReaderPrefetchQueue);
  }

  static void _clearReaderPrefetchQueue(Queue<_ReaderPrefetchRequest> queue) {
    while (queue.isNotEmpty) {
      final _ReaderPrefetchRequest request = queue.removeFirst();
      _queuedReaderPrefetchUrls.remove(request.url);
    }
  }

  static void _drainReaderPrefetchQueue() {
    final bool priorityPhase =
        _priorityReaderPrefetchQueue.isNotEmpty ||
        _activeReaderPrefetchUrls.any(_priorityReaderPrefetchUrls.contains);
    if (priorityPhase) {
      while (_activeReaderPrefetches < readerPrefetchConcurrency &&
          _priorityReaderPrefetchQueue.isNotEmpty) {
        _startReaderPrefetch(_priorityReaderPrefetchQueue.removeFirst());
      }
      return;
    }

    while (_activeReaderPrefetches < readerPrefetchConcurrency &&
        _normalReaderPrefetchQueue.isNotEmpty) {
      _startReaderPrefetch(_normalReaderPrefetchQueue.removeFirst());
    }
  }

  static void _startReaderPrefetch(_ReaderPrefetchRequest request) {
    _activeReaderPrefetches += 1;
    _activeReaderPrefetchUrls.add(request.url);
    unawaited(_runReaderPrefetch(request));
  }

  static Future<void> _runReaderPrefetch(_ReaderPrefetchRequest request) async {
    try {
      await readerCache.getSingleFile(
        request.url,
        headers: readerImageHeaders(request.referer),
      );
    } catch (_) {
      return;
    } finally {
      _queuedReaderPrefetchUrls.remove(request.url);
      _activeReaderPrefetchUrls.remove(request.url);
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
