import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/services/local_library_store.dart';
import 'package:easy_copy/services/site_session.dart';

typedef ResolveReaderHistoryCover = String Function(String catalogHref);

class ReaderHistoryRecorder {
  ReaderHistoryRecorder({
    required this.resolveCoverUrl,
    LocalLibraryStore? localLibraryStore,
    SiteSession? session,
  }) : _localLibraryStore = localLibraryStore ?? LocalLibraryStore.instance,
       _session = session ?? SiteSession.instance;

  final ResolveReaderHistoryCover resolveCoverUrl;
  final LocalLibraryStore _localLibraryStore;
  final SiteSession _session;

  Future<void> recordVisit(ReaderPageData page) async {
    try {
      final String coverUrl = resolveCoverUrl(page.catalogHref);

      try {
        await _localLibraryStore.recordHistoryFromReader(
          LocalLibraryStore.continueReadingScope,
          page,
          coverUrl: coverUrl,
        );
      } catch (_) {}

      if (!_session.isAuthenticated) {
        try {
          await _localLibraryStore.recordHistoryFromReader(
            LocalLibraryStore.guestScope,
            page,
            coverUrl: coverUrl,
          );
        } catch (_) {}
      }
    } catch (_) {}
  }
}
