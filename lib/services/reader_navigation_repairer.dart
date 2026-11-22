import 'package:reader/config/app_config.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/services/local_comic.dart';
import 'package:reader/services/page_cache_store.dart';

typedef ReaderNavigationPageLoader =
    Future<ReaderPageData?> Function(Uri uri, {required String authScope});
typedef RepairCatalog = ({DetailPageData page, DateTime validatedAt});
typedef ReaderNavigationDetailLoader =
    Future<RepairCatalog?> Function(Uri uri, {required String authScope});

class ReaderNavigationRepairer {
  DetailPageData? _catalog;
  String? _scope;
  DateTime? _expires;

  void rememberCatalog(
    DetailPageData page,
    String authScope,
    DateTime validatedAt,
  ) {
    _catalog = page;
    _scope = authScope;
    _expires = validatedAt.add(PageCachePolicy.detailPage.softTtl);
  }

  bool hasConfirmedNavigation(ReaderPageData page, String scope) {
    final catalog = _catalog;
    if (catalog == null ||
        _scope != scope ||
        !DateTime.now().isBefore(_expires!) ||
        catalog.uri != page.catalogHref) {
      return false;
    }
    final links = catalog.adjacentTo(page.uri);
    return links != null &&
        (page.prevHref.isNotEmpty || links.prevHref.isEmpty) &&
        (page.nextHref.isNotEmpty || links.nextHref.isEmpty);
  }

  Future<ReaderPageData> repair(
    ReaderPageData page, {
    required String authScope,
    required ReaderNavigationPageLoader loadReaderPage,
    required ReaderNavigationDetailLoader loadDetailPage,
    String preferredCatalogHref = '',
  }) async {
    if (isLocalComic(page.uri) ||
        !page.hasMissingChapterNavigation ||
        hasConfirmedNavigation(page, authScope)) {
      return page;
    }

    final Uri? detailUri = _detailUriForPage(
      page,
      preferredCatalogHref: preferredCatalogHref,
    );
    if (detailUri != null) {
      try {
        var detailPage = _catalog;
        if (detailPage == null ||
            _scope != authScope ||
            !DateTime.now().isBefore(_expires!) ||
            detailPage.uri != detailUri.toString() ||
            detailPage.adjacentTo(page.uri) == null) {
          final result = await loadDetailPage(detailUri, authScope: authScope);
          detailPage = result?.page;
          if (result != null) {
            rememberCatalog(result.page, authScope, result.validatedAt);
          }
        }
        if (detailPage != null) {
          final links = detailPage.adjacentTo(page.uri);
          if (links != null) {
            return page.mergeMissingNavigation(
              prevHref: links.prevHref,
              nextHref: links.nextHref,
              catalogHref: detailPage.uri,
            );
          }
        }
      } catch (_) {
        // 没有可用目录时，才尝试从章节页补齐链接。
      }
    }

    try {
      final ReaderPageData? freshReaderPage = await loadReaderPage(
        Uri.parse(page.uri),
        authScope: authScope,
      );
      if (freshReaderPage != null) {
        return page.mergeMissingNavigation(
          prevHref: freshReaderPage.prevHref,
          nextHref: freshReaderPage.nextHref,
          catalogHref: freshReaderPage.catalogHref,
        );
      }
    } catch (_) {
      // 修复失败保留原页面，后续可重试。
    }
    return page;
  }

  static Uri? _detailUriForPage(
    ReaderPageData page, {
    required String preferredCatalogHref,
  }) {
    for (final String candidate in <String>[
      preferredCatalogHref,
      page.catalogHref,
    ]) {
      final String trimmed = candidate.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final Uri resolved = AppConfig.resolveNavigationUri(
        trimmed,
        currentUri: Uri.parse(page.uri),
      );
      if (AppConfig.isDetailCatalogUri(resolved)) {
        return resolved;
      }
    }

    final Uri readerUri = AppConfig.rewriteToCurrentHost(Uri.parse(page.uri));
    final List<String> segments = readerUri.pathSegments;
    final int chapterIndex = segments.indexOf('chapter');
    if (chapterIndex <= 0) {
      return null;
    }
    return readerUri.replace(
      pathSegments: segments.take(chapterIndex).toList(growable: false),
      queryParameters: null,
      fragment: null,
    );
  }
}
