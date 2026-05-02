import 'package:easy_copy/models/page_models.dart';

typedef ReaderPageMaybeLoader = Future<ReaderPageData?> Function(Uri uri);
typedef ReaderPageLoader = Future<ReaderPageData> Function(Uri uri);

class ReaderPageDownloadResolver {
  const ReaderPageDownloadResolver._();

  static Future<ReaderPageData> resolve(
    Uri chapterUri, {
    required ReaderPageMaybeLoader loadFromStorageCache,
    required ReaderPageMaybeLoader loadFromPageCache,
    required ReaderPageLoader loadFromLightweightSource,
    required ReaderPageLoader loadFromWebViewFallback,
  }) async {
    bool hasUsableImageList(ReaderPageData? page) {
      return page != null && page.imageUrls.isNotEmpty;
    }

    final ReaderPageData? storageCachedPage = await loadFromStorageCache(
      chapterUri,
    );
    if (hasUsableImageList(storageCachedPage)) {
      return storageCachedPage!;
    }

    final ReaderPageData? pageCachedPage = await loadFromPageCache(chapterUri);
    if (hasUsableImageList(pageCachedPage)) {
      return pageCachedPage!;
    }

    try {
      final ReaderPageData lightweightPage = await loadFromLightweightSource(
        chapterUri,
      );
      if (hasUsableImageList(lightweightPage)) {
        return lightweightPage;
      }
    } catch (_) {
      // Let WebView fallback handle parser incompatibilities.
    }

    return loadFromWebViewFallback(chapterUri);
  }
}
