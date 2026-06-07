import 'dart:async';

import 'package:reader/config/app_config.dart';
import 'package:reader/services/navigation_request_guard.dart';
import 'package:reader/services/page_repository.dart';
import 'package:reader/services/primary_tab_session_store.dart';

enum StandardPageLoadEventSource {
  navigationRequest,
  urlChange,
  pageStarted,
  pageFinished,
  mainFrameError,
  payload,
}

class SupersededPageLoadException implements Exception {
  const SupersededPageLoadException();

  @override
  String toString() => '页面加载已被更新的导航替换。';
}

class StandardPageLoadHandle<T> {
  StandardPageLoadHandle({
    required Uri requestedUri,
    required this.queryKey,
    required this.loadId,
    required this.requestContext,
    required this.completer,
  }) : requestedUri = AppConfig.rewriteToCurrentHost(requestedUri),
       acceptedRouteKeys = <String>{queryKey.routeKey};

  final Uri requestedUri;
  final PageQueryKey queryKey;
  final int loadId;
  final NavigationRequestContext requestContext;
  final Completer<T> completer;
  final Set<String> acceptedRouteKeys;
  final Set<String> startedRouteKeys = <String>{};

  bool hasStartedAcceptedNavigation = false;
  Uri? lastStartedAcceptedUri;

  NavigationIntent get intent => requestContext.intent;

  bool get preserveCurrentPage => requestContext.preserveVisiblePage;

  int get targetTabIndex => requestContext.targetTabIndex;

  bool accepts(Uri uri, {required StandardPageLoadEventSource source}) {
    final Uri rewrittenUri = AppConfig.rewriteToCurrentHost(uri);
    final String routeKey = AppConfig.routeKeyForUri(rewrittenUri);
    final bool isAcceptedRoute = acceptedRouteKeys.contains(routeKey);

    switch (source) {
      case StandardPageLoadEventSource.navigationRequest:
      case StandardPageLoadEventSource.urlChange:
        if (isAcceptedRoute) {
          return true;
        }
        if (_canAcceptRedirectTo(rewrittenUri)) {
          acceptedRouteKeys.add(routeKey);
          return true;
        }
        return false;
      case StandardPageLoadEventSource.pageStarted:
        if (!isAcceptedRoute) {
          return false;
        }
        startedRouteKeys.add(routeKey);
        hasStartedAcceptedNavigation = true;
        lastStartedAcceptedUri = rewrittenUri;
        return true;
      case StandardPageLoadEventSource.pageFinished:
      case StandardPageLoadEventSource.payload:
        return startedRouteKeys.contains(routeKey);
      case StandardPageLoadEventSource.mainFrameError:
        return acceptedRouteKeys.contains(routeKey);
    }
  }

  bool _canAcceptRedirectTo(Uri candidateUri) {
    final Uri anchorUri = lastStartedAcceptedUri ?? requestedUri;
    if (_isSameContentRedirect(anchorUri, candidateUri)) {
      return true;
    }
    return false;
  }
}

bool _isSameContentRedirect(Uri from, Uri to) {
  if (from.path != to.path) {
    return false;
  }
  final String path = from.path.toLowerCase();
  return _isDetailRoute(path) || path.contains('/chapter/');
}

bool _isDetailRoute(String path) {
  return path.startsWith('/comic/') && !path.contains('/chapter/');
}

class StandardPageLoadController<T> {
  StandardPageLoadHandle<T>? _pendingLoad;

  StandardPageLoadHandle<T>? get pendingLoad => _pendingLoad;

  StandardPageLoadHandle<T> begin(StandardPageLoadHandle<T> load) {
    final StandardPageLoadHandle<T>? previous = _pendingLoad;
    if (previous != null &&
        !identical(previous, load) &&
        !previous.completer.isCompleted) {
      previous.completer.completeError(const SupersededPageLoadException());
    }
    _pendingLoad = load;
    return load;
  }

  bool isCurrent(StandardPageLoadHandle<T> load) {
    return identical(_pendingLoad, load);
  }

  void clear(StandardPageLoadHandle<T> load) {
    if (identical(_pendingLoad, load)) {
      _pendingLoad = null;
    }
  }
}

StandardPageLoadHandle<T>? acceptedPendingNavigationLoad<T>(
  StandardPageLoadHandle<T>? pendingLoad,
  Uri uri, {
  required StandardPageLoadEventSource source,
}) {
  if (pendingLoad == null || pendingLoad.completer.isCompleted) {
    return null;
  }
  if (!pendingLoad.accepts(uri, source: source)) {
    return null;
  }
  return pendingLoad;
}
