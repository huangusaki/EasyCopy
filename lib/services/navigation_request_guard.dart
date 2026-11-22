import 'package:flutter/foundation.dart';
import 'package:reader/services/primary_tab_session_store.dart';

@immutable
class NavigationRequestContext {
  const NavigationRequestContext({
    required this.requestId,
    required this.targetTabIndex,
    required this.routeKey,
    required this.preserveVisiblePage,
  });

  final int requestId;
  final int targetTabIndex;
  final String routeKey;
  final bool preserveVisiblePage;
}

bool canCommitNavigationRequest({
  required int currentSelectedIndex,
  required PrimaryTabRouteEntry currentEntry,
  required NavigationRequestContext request,
}) {
  return currentSelectedIndex == request.targetTabIndex &&
      currentEntry.activeRequestId == request.requestId;
}
