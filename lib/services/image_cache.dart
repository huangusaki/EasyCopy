import 'dart:async';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class EasyCopyImageCaches {
  EasyCopyImageCaches._();

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

  static Future<void> prefetchReaderImages(Iterable<String> urls) async {
    for (final String url in urls.take(6)) {
      unawaited(readerCache.downloadFile(url));
    }
  }
}
