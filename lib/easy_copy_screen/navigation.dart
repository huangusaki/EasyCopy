part of '../easy_copy_screen.dart';

extension _EasyCopyScreenNavigation on _EasyCopyScreenState {
  PrimaryTabRouteEntry get _currentEntry =>
      _tabSessionStore.currentEntry(_selectedIndex);

  StandardPageLoadHandle<EasyCopyPage>? get _pendingPageLoad =>
      _standardPageLoadController.pendingLoad;

  Uri get _currentUri => _currentEntry.uri;

  EasyCopyPage? get _page => _currentEntry.page;

  bool get _isLoading => _currentEntry.isLoading;

  String? get _errorMessage => _currentEntry.errorMessage;

  String _authScopeForUri(Uri uri) {
    if (_isProfileUri(uri) || _isUserScopedDetailUri(uri)) {
      return _session.authScope;
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
      requestId: ++_nextNavigationRequestId,
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
      currentSelectedIndex: _selectedIndex,
      currentEntry: _tabSessionStore.currentEntry(request.targetTabIndex),
      request: request,
    );
  }

  void _recordSupersededRequest(
    NavigationRequestContext request, {
    required String phase,
  }) {
    _supersededNavigationRequestCount += 1;
    if (!kDebugMode) {
      return;
    }
    debugPrint(
      '[nav] superseded request=${request.requestId} '
      'tab=${request.targetTabIndex} route=${request.routeKey} phase=$phase '
      'count=$_supersededNavigationRequestCount',
    );
  }

  void _recordDiscardedNavigationMutation(
    NavigationRequestContext request, {
    required String phase,
  }) {
    _discardedNavigationCommitCount += 1;
    if (!kDebugMode) {
      return;
    }
    debugPrint(
      '[nav] discarded commit request=${request.requestId} '
      'tab=${request.targetTabIndex} route=${request.routeKey} phase=$phase '
      'count=$_discardedNavigationCommitCount',
    );
  }

  void _recordDiscardedNavigationCallback(
    NavigationRequestContext request, {
    required String phase,
  }) {
    _discardedNavigationCallbackCount += 1;
    if (!kDebugMode) {
      return;
    }
    debugPrint(
      '[nav] discarded callback request=${request.requestId} '
      'tab=${request.targetTabIndex} route=${request.routeKey} phase=$phase '
      'count=$_discardedNavigationCallbackCount',
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
      _recordDiscardedNavigationMutation(request, phase: phase);
      return false;
    }
    _mutateSessionState(() {
      _tabSessionStore.updateCurrent(request.targetTabIndex, updater);
    }, syncSearch: request.targetTabIndex == _selectedIndex);
    return true;
  }

  bool _shouldActivateAsyncResultTab(int targetTabIndex) {
    return shouldActivateTargetTab(
      currentSelectedIndex: _selectedIndex,
      targetTabIndex: targetTabIndex,
      phase: TabActivationPhase.asyncLoadResult,
    );
  }
}
