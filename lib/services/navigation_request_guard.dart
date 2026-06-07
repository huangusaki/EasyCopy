import 'package:flutter/foundation.dart';
import 'package:reader/services/primary_tab_session_store.dart';

enum NavigationRequestSourceKind {
  navigation,
  cachedReader,
  profile,
  revalidate,
}

@immutable
class NavigationRequestContext {
  const NavigationRequestContext({
    required this.requestId,
    required this.targetTabIndex,
    required this.routeKey,
    required this.intent,
    required this.preserveVisiblePage,
    required this.sourceKind,
    this.allowBackgroundCache = true,
  });

  final int requestId;
  final int targetTabIndex;
  final String routeKey;
  final NavigationIntent intent;
  final bool preserveVisiblePage;
  final NavigationRequestSourceKind sourceKind;
  final bool allowBackgroundCache;

  NavigationRequestContext copyWith({
    int? requestId,
    int? targetTabIndex,
    String? routeKey,
    NavigationIntent? intent,
    bool? preserveVisiblePage,
    NavigationRequestSourceKind? sourceKind,
    bool? allowBackgroundCache,
  }) {
    return NavigationRequestContext(
      requestId: requestId ?? this.requestId,
      targetTabIndex: targetTabIndex ?? this.targetTabIndex,
      routeKey: routeKey ?? this.routeKey,
      intent: intent ?? this.intent,
      preserveVisiblePage: preserveVisiblePage ?? this.preserveVisiblePage,
      sourceKind: sourceKind ?? this.sourceKind,
      allowBackgroundCache: allowBackgroundCache ?? this.allowBackgroundCache,
    );
  }
}

bool canCommitNavigationRequest({
  required int currentSelectedIndex,
  required PrimaryTabRouteEntry currentEntry,
  required NavigationRequestContext request,
}) {
  return currentSelectedIndex == request.targetTabIndex &&
      currentEntry.activeRequestId == request.requestId;
}
