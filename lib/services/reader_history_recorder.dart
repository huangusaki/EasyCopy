import 'package:reader/models/page_models.dart';
import 'package:reader/services/local_library_store.dart';
import 'package:reader/services/site_session.dart';

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
      } catch (_) {
        // 忽略继续阅读写入失败。
      }

      if (!_session.isAuthenticated) {
        try {
          await _localLibraryStore.recordHistoryFromReader(
            LocalLibraryStore.guestScope,
            page,
            coverUrl: coverUrl,
          );
        } catch (_) {
          // 忽略访客历史写入失败。
        }
      }
    } catch (_) {
      // 历史记录失败不影响阅读。
    }
  }
}
