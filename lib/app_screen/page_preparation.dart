import 'dart:async';

import 'package:reader/app_screen/session_controller.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/services/local_library_store.dart';
import 'package:reader/services/page_repository.dart';

/// Owns the session and route that may prepare and persist one page result.
class PagePreparation {
  PagePreparation({
    required AppSessionController sessionController,
    required PageRepository pageRepository,
    required LocalLibraryStore localLibraryStore,
    required this.sessionGeneration,
    required this.authScope,
    required bool Function() isRequestCurrent,
  }) : _sessionController = sessionController,
       _pageRepository = pageRepository,
       _localLibraryStore = localLibraryStore,
       _isRequestCurrent = isRequestCurrent;

  final AppSessionController _sessionController;
  final PageRepository _pageRepository;
  final LocalLibraryStore _localLibraryStore;
  final bool Function() _isRequestCurrent;
  final int sessionGeneration;
  final String authScope;

  bool get isCurrent =>
      _sessionController.accepts(sessionGeneration) && _isRequestCurrent();

  Future<SitePage?> prepare(FutureOr<SitePage> pendingPage) async {
    final SitePage page = await pendingPage;
    if (!isCurrent) return null;
    if (page is! DetailPageData || authScope != LocalLibraryStore.guestScope) {
      return page;
    }
    try {
      final bool isCollected = await _localLibraryStore.isCollected(
        authScope,
        page.uri,
      );
      if (!isCurrent) return null;
      if (isCollected == page.isCollected) return page;
      final DetailPageData updated = page.copyWith(isCollected: isCollected);
      unawaited(persistDetail(updated));
      return updated;
    } catch (_) {
      return isCurrent ? page : null;
    }
  }

  Future<void> persistDetail(DetailPageData page) async {
    if (!isCurrent) return;
    try {
      await _pageRepository.writeCachedPage(page, authScope: authScope);
    } catch (_) {
      // A cache repair must not prevent the page from opening.
    }
  }
}
