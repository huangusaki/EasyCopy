import 'package:reader/services/page_repository.dart';
import 'package:reader/services/site_session.dart';

/// Coordinates session teardown before asynchronous cache and platform cleanup.
class AppSessionController {
  AppSessionController({
    required SiteSession session,
    required PageRepository pageRepository,
    required void Function() invalidateNavigation,
    required Future<void> Function() clearPlatformCookies,
  }) : _session = session,
       _pageRepository = pageRepository,
       _invalidateNavigation = invalidateNavigation,
       _clearPlatformCookies = clearPlatformCookies;

  final SiteSession _session;
  final PageRepository _pageRepository;
  final void Function() _invalidateNavigation;
  final Future<void> Function() _clearPlatformCookies;
  bool _isLoggingOut = false;
  int _generation = 0;

  bool get isLoggingOut => _isLoggingOut;
  int get generation => _generation;
  bool accepts(int generation) => !_isLoggingOut && generation == _generation;

  Future<void> logout() async {
    if (_isLoggingOut) return;
    _isLoggingOut = true;
    _generation += 1;
    try {
      _invalidateNavigation();
      // SiteSession.clear clears its in-memory token synchronously. Enqueue all
      // cleanup before yielding so no old account can acquire a new cache epoch.
      await Future.wait<void>(<Future<void>>[
        _session.clear(),
        _pageRepository.removeAuthenticatedEntries(),
        _clearPlatformCookies(),
      ]);
    } finally {
      _isLoggingOut = false;
    }
  }
}
