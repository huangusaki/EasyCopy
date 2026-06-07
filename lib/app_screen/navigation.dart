part of '../app_screen.dart';

extension _AppScreenNavigation on _AppScreenState {
  PrimaryTabRouteEntry get _currentEntry =>
      _tabSessionStore.currentEntry(_nav.selectedIndex);

  StandardPageLoadHandle<SitePage>? get _pendingPageLoad =>
      _standardPageLoadController.pendingLoad;

  Uri get _currentUri => _currentEntry.uri;

  SitePage? get _page => _currentEntry.page;

  bool get _isLoading => _currentEntry.isLoading;

  String? get _errorMessage => _currentEntry.errorMessage;

  String _authScopeForUri(Uri uri) {
    if (isProfileUri(uri) || _routes.isUserScopedDetailUri(uri)) {
      return _services.session.authScope;
    }
    return 'guest';
  }

  PageQueryKey _pageQueryKeyForUri(Uri uri, {String? authScope}) {
    return PageQueryKey.forUri(
      uri,
      authScope: authScope ?? _authScopeForUri(uri),
    );
  }

  NavigationRequestContext _createNavigationRequestContext(
    Uri uri, {
    required int targetTabIndex,
    required NavigationIntent intent,
    required bool preserveVisiblePage,
    required NavigationRequestSourceKind sourceKind,
    bool allowBackgroundCache = true,
  }) {
    final Uri targetUri = AppConfig.rewriteToCurrentHost(uri);
    return NavigationRequestContext(
      requestId: ++_nav.nextNavigationRequestId,
      targetTabIndex: targetTabIndex,
      routeKey: AppConfig.routeKeyForUri(targetUri),
      intent: intent,
      preserveVisiblePage: preserveVisiblePage,
      sourceKind: sourceKind,
      allowBackgroundCache: allowBackgroundCache,
    );
  }

  bool _canCommitRequest(NavigationRequestContext request) {
    return canCommitNavigationRequest(
      currentSelectedIndex: _nav.selectedIndex,
      currentEntry: _tabSessionStore.currentEntry(request.targetTabIndex),
      request: request,
    );
  }

  void _recordSupersededRequest(
    NavigationRequestContext request, {
    required String phase,
  }) {
    _nav.supersededRequestCount += 1;
    if (!kDebugMode) {
      return;
    }
    debugPrint(
      '[nav] superseded request=${request.requestId} '
      'tab=${request.targetTabIndex} route=${request.routeKey} phase=$phase '
      'count=${_nav.supersededRequestCount}',
    );
  }

  void _recordDiscardedMutation(
    NavigationRequestContext request, {
    required String phase,
  }) {
    _nav.discardedNavigationCommitCount += 1;
    if (!kDebugMode) {
      return;
    }
    debugPrint(
      '[nav] discarded commit request=${request.requestId} '
      'tab=${request.targetTabIndex} route=${request.routeKey} phase=$phase '
      'count=${_nav.discardedNavigationCommitCount}',
    );
  }

  void _recordDiscardedCallback(
    NavigationRequestContext request, {
    required String phase,
  }) {
    _nav.discardedCallbackCount += 1;
    if (!kDebugMode) {
      return;
    }
    debugPrint(
      '[nav] discarded callback request=${request.requestId} '
      'tab=${request.targetTabIndex} route=${request.routeKey} phase=$phase '
      'count=${_nav.discardedCallbackCount}',
    );
  }

  void _abandonCurrentRequest(int tabIndex, {required String phase}) {
    final PrimaryTabRouteEntry entry = _tabSessionStore.currentEntry(tabIndex);
    if (entry.activeRequestId == 0) {
      return;
    }
    _recordSupersededRequest(
      NavigationRequestContext(
        requestId: entry.activeRequestId,
        targetTabIndex: tabIndex,
        routeKey: entry.routeKey,
        intent: NavigationIntent.preserve,
        preserveVisiblePage: true,
        sourceKind: NavigationRequestSourceKind.navigation,
      ),
      phase: phase,
    );
    _tabSessionStore.abandonCurrentRequest(tabIndex);
  }

  bool _mutateOwnedRequestEntry(
    NavigationRequestContext request,
    PrimaryTabRouteEntry Function(PrimaryTabRouteEntry entry) updater, {
    required String phase,
  }) {
    if (!_canCommitRequest(request)) {
      _recordDiscardedMutation(request, phase: phase);
      return false;
    }
    _mutateSessionState(() {
      _tabSessionStore.updateCurrent(request.targetTabIndex, updater);
    }, syncSearch: request.targetTabIndex == _nav.selectedIndex);
    return true;
  }

  bool _shouldActivateAsyncResultTab(int targetTabIndex) {
    return shouldActivateTargetTab(
      currentSelectedIndex: _nav.selectedIndex,
      targetTabIndex: targetTabIndex,
      phase: TabActivationPhase.asyncLoadResult,
    );
  }
}
