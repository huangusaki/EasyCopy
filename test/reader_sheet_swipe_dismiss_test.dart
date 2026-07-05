import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/reader/reader_sheet_swipe_dismiss.dart';

void main() {
  Widget buildTestWidget({required VoidCallback onDismiss}) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ReaderSheetSwipeDismissRegion(
        dismissDistance: 72,
        onDismiss: onDismiss,
        child: const SizedBox(width: 300, height: 300),
      ),
    );
  }

  testWidgets('ignores short downward swipe on reader settings sheet', (
    WidgetTester tester,
  ) async {
    var dismissCount = 0;
    await tester.pumpWidget(
      buildTestWidget(onDismiss: () => dismissCount += 1),
    );

    final TestGesture gesture = await tester.startGesture(
      const Offset(150, 100),
    );
    await gesture.moveBy(const Offset(0, 96));
    await gesture.up();
    await tester.pump();

    expect(dismissCount, 0);
  });

  testWidgets('dismisses after intentional downward swipe', (
    WidgetTester tester,
  ) async {
    var dismissCount = 0;
    await tester.pumpWidget(
      buildTestWidget(onDismiss: () => dismissCount += 1),
    );

    final TestGesture gesture = await tester.startGesture(
      const Offset(150, 100),
    );
    await gesture.moveBy(const Offset(0, 128));
    await gesture.up();
    await tester.pump();

    expect(dismissCount, 1);
  });
}
