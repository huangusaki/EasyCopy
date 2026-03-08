enum TabActivationPhase { navigationRequest, asyncLoadResult }

bool shouldActivateTargetTab({
  required int currentSelectedIndex,
  required int targetTabIndex,
  required TabActivationPhase phase,
}) {
  switch (phase) {
    case TabActivationPhase.navigationRequest:
      return true;
    case TabActivationPhase.asyncLoadResult:
      return currentSelectedIndex == targetTabIndex;
  }
}
