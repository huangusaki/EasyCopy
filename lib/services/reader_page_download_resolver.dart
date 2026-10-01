import 'package:reader/models/page_models.dart';

typedef ReaderPageMaybeLoader = Future<ReaderPageData?> Function(Uri uri);
typedef ReaderPageLoader = Future<ReaderPageData> Function(Uri uri);

class ReaderPageDownloadResolver {
  const ReaderPageDownloadResolver({
    required ReaderPageMaybeLoader loadFromStorageCache,
    required ReaderPageMaybeLoader loadFromPageCache,
    required ReaderPageLoader loadFromLightweightSource,
    required ReaderPageLoader loadFromWebViewFallback,
  }) : _loadFromStorageCache = loadFromStorageCache,
       _loadFromPageCache = loadFromPageCache,
       _loadFromLightweightSource = loadFromLightweightSource,
       _loadFromWebViewFallback = loadFromWebViewFallback;

  final ReaderPageMaybeLoader _loadFromStorageCache;
  final ReaderPageMaybeLoader _loadFromPageCache;
  final ReaderPageLoader _loadFromLightweightSource;
  final ReaderPageLoader _loadFromWebViewFallback;

  Future<ReaderPageData> resolve(Uri chapterUri) async {
    final ReaderPageData? pageCachedPage = await _loadFromPageCache(chapterUri);
    if (_hasRemoteImageList(pageCachedPage)) {
      return pageCachedPage!;
    }

    // The storage loader validates local images or returns saved remote sources.
    final ReaderPageData? storageCachedPage = await _loadFromStorageCache(
      chapterUri,
    );
    if (_hasUsableImageList(storageCachedPage)) {
      return storageCachedPage!;
    }

    try {
      final ReaderPageData lightweightPage = await _loadFromLightweightSource(
        chapterUri,
      );
      if (_hasRemoteImageList(lightweightPage)) {
        return lightweightPage;
      }
    } catch (_) {
      // Let WebView fallback handle parser incompatibilities.
    }

    final ReaderPageData page = await _loadFromWebViewFallback(chapterUri);
    if (!_hasRemoteImageList(page)) {
      throw StateError('章节解析失败');
    }
    return page;
  }

  bool _hasUsableImageList(ReaderPageData? page) {
    return page != null && page.imageUrls.isNotEmpty;
  }

  bool _hasRemoteImageList(ReaderPageData? page) {
    return _hasUsableImageList(page) &&
        page!.imageUrls.every((String url) {
          final Uri? uri = Uri.tryParse(url);
          return uri != null &&
              (uri.scheme == 'http' || uri.scheme == 'https') &&
              uri.host.isNotEmpty;
        });
  }
}
