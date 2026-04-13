import 'package:easy_copy/config/app_config.dart';
import 'package:easy_copy/models/page_models.dart';

typedef ReaderNavigationPageLoader =
    Future<ReaderPageData?> Function(Uri uri, {required String authScope});
typedef ReaderNavigationDetailLoader =
    Future<DetailPageData?> Function(Uri uri, {required String authScope});

class ReaderNavigationRepairer {
  const ReaderNavigationRepairer._();

  static Future<ReaderPageData> repair(
    ReaderPageData page, {
    required String authScope,
    required ReaderNavigationPageLoader loadReaderPage,
    required ReaderNavigationDetailLoader loadDetailPage,
    String preferredCatalogHref = '',
  }) async {
    if (!page.hasMissingChapterNavigation) {
      return page;
    }

    ReaderPageData repairedPage = page;

    try {
      final ReaderPageData? freshReaderPage = await loadReaderPage(
        Uri.parse(page.uri),
        authScope: authScope,
      );
      if (freshReaderPage != null) {
        repairedPage = repairedPage.mergeMissingNavigation(
          prevHref: freshReaderPage.prevHref,
          nextHref: freshReaderPage.nextHref,
          catalogHref: freshReaderPage.catalogHref,
        );
      }
    } catch (_) {
      // Best-effort repair only.
    }

    if (!repairedPage.hasMissingChapterNavigation) {
      return repairedPage;
    }

    final Uri? detailUri = _detailUriForPage(
      repairedPage,
      preferredCatalogHref: preferredCatalogHref,
    );
    if (detailUri == null) {
      return repairedPage;
    }

    try {
      final DetailPageData? detailPage = await loadDetailPage(
        detailUri,
        authScope: authScope,
      );
      if (detailPage == null) {
        return repairedPage;
      }
      final _AdjacentChapterLinks links = _adjacentChapterLinks(
        detailPage,
        repairedPage.uri,
      );
      return repairedPage.mergeMissingNavigation(
        prevHref: links.prevHref,
        nextHref: links.nextHref,
        catalogHref: detailPage.uri,
      );
    } catch (_) {
      return repairedPage;
    }
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
      if (_isDetailUri(resolved)) {
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

  static bool _isDetailUri(Uri uri) {
    final String path = uri.path.toLowerCase();
    return path.startsWith('/comic/') && !path.contains('/chapter/');
  }

  static _AdjacentChapterLinks _adjacentChapterLinks(
    DetailPageData page,
    String currentChapterHref,
  ) {
    final List<ChapterData> chapters = page.chapters.isNotEmpty
        ? page.chapters
        : page.chapterGroups
              .expand((ChapterGroupData group) => group.chapters)
              .toList(growable: false);
    final String currentKey = _chapterPathKey(currentChapterHref);
    final int index = chapters.indexWhere(
      (ChapterData chapter) => _chapterPathKey(chapter.href) == currentKey,
    );
    if (index == -1) {
      return const _AdjacentChapterLinks();
    }
    return _AdjacentChapterLinks(
      prevHref: index > 0 ? chapters[index - 1].href : '',
      nextHref: index + 1 < chapters.length ? chapters[index + 1].href : '',
    );
  }

  static String _chapterPathKey(String href) {
    final Uri? uri = Uri.tryParse(href);
    if (uri == null) {
      return '';
    }
    return Uri(path: AppConfig.rewriteToCurrentHost(uri).path).toString();
  }
}

class _AdjacentChapterLinks {
  const _AdjacentChapterLinks({this.prevHref = '', this.nextHref = ''});

  final String prevHref;
  final String nextHref;
}
