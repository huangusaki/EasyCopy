import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/widgets/responsive_layout.dart';

void main() {
  testWidgets('Android wide screens keep the mobile window shell', (
    WidgetTester tester,
  ) async {
    late bool usesWideLayout;
    late bool usesDesktopShell;

    await tester.pumpWidget(
      _LayoutProbe(
        platform: TargetPlatform.android,
        size: const Size(1280, 800),
        onBuild: (BuildContext context) {
          usesWideLayout = usesDesktopLayout(context);
          usesDesktopShell = usesDesktopWindowShell(context);
        },
      ),
    );

    expect(usesWideLayout, isTrue);
    expect(usesDesktopShell, isFalse);
  });

  testWidgets('Windows wide screens use the desktop window shell', (
    WidgetTester tester,
  ) async {
    late bool usesDesktopShell;

    await tester.pumpWidget(
      _LayoutProbe(
        platform: TargetPlatform.windows,
        size: const Size(1280, 800),
        onBuild: (BuildContext context) {
          usesDesktopShell = usesDesktopWindowShell(context);
        },
      ),
    );

    expect(usesDesktopShell, isTrue);
  });

  testWidgets('Windows compact screens keep the mobile window shell', (
    WidgetTester tester,
  ) async {
    late bool usesDesktopShell;

    await tester.pumpWidget(
      _LayoutProbe(
        platform: TargetPlatform.windows,
        size: const Size(800, 1280),
        onBuild: (BuildContext context) {
          usesDesktopShell = usesDesktopWindowShell(context);
        },
      ),
    );

    expect(usesDesktopShell, isFalse);
  });
}

class _LayoutProbe extends StatelessWidget {
  const _LayoutProbe({
    required this.platform,
    required this.size,
    required this.onBuild,
  });

  final TargetPlatform platform;
  final Size size;
  final ValueChanged<BuildContext> onBuild;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(platform: platform),
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Builder(
          builder: (BuildContext context) {
            onBuild(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}
