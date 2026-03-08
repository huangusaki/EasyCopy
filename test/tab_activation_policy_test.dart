import 'package:easy_copy/services/tab_activation_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('navigation requests always activate the requested tab immediately', () {
    expect(
      shouldActivateTargetTab(
        currentSelectedIndex: 0,
        targetTabIndex: 3,
        phase: TabActivationPhase.navigationRequest,
      ),
      isTrue,
    );
    expect(
      shouldActivateTargetTab(
        currentSelectedIndex: 3,
        targetTabIndex: 1,
        phase: TabActivationPhase.navigationRequest,
      ),
      isTrue,
    );
  });

  test('async results only reactivate tabs that remain selected', () {
    expect(
      shouldActivateTargetTab(
        currentSelectedIndex: 3,
        targetTabIndex: 3,
        phase: TabActivationPhase.asyncLoadResult,
      ),
      isTrue,
    );
    expect(
      shouldActivateTargetTab(
        currentSelectedIndex: 0,
        targetTabIndex: 3,
        phase: TabActivationPhase.asyncLoadResult,
      ),
      isFalse,
    );
  });

  test(
    'profile refresh, cached hits, and revalidate share the same async rule',
    () {
      expect(
        shouldActivateTargetTab(
          currentSelectedIndex: 1,
          targetTabIndex: 3,
          phase: TabActivationPhase.asyncLoadResult,
        ),
        isFalse,
      );
      expect(
        shouldActivateTargetTab(
          currentSelectedIndex: 3,
          targetTabIndex: 1,
          phase: TabActivationPhase.asyncLoadResult,
        ),
        isFalse,
      );
      expect(
        shouldActivateTargetTab(
          currentSelectedIndex: 0,
          targetTabIndex: 2,
          phase: TabActivationPhase.asyncLoadResult,
        ),
        isFalse,
      );
    },
  );
}
