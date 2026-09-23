import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/config/app_config.dart';
import 'package:reader/widgets/desktop/desktop_dock.dart';
import 'package:reader/widgets/mobile_floating_nav_bar.dart';
import 'package:reader/widgets/standard_bottom_inset.dart';

void main() {
  testWidgets('移动端只避让一次，显隐与键盘变化后末项仍可点击', (tester) async {
    final ValueNotifier<bool> visible = ValueNotifier<bool>(true);
    final ScrollController scroll = ScrollController();
    addTearDown(visible.dispose);
    addTearDown(scroll.dispose);
    const Key insetKey = ValueKey<String>('inset');
    int taps = 0;

    Future<void> show(double safeBottom, {double keyboard = 0}) =>
        tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.android),
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(800, 600),
                padding: EdgeInsets.only(bottom: safeBottom),
                viewPadding: EdgeInsets.only(bottom: safeBottom),
                viewInsets: EdgeInsets.only(bottom: keyboard),
              ),
              child: Scaffold(
                extendBody: true,
                bottomNavigationBar: MobileFloatingNavBar(
                  selectedIndex: 0,
                  destinations: appDestinations,
                  onDestinationSelected: (_) {},
                  visibleListenable: visible,
                ),
                body: SafeArea(
                  bottom: false,
                  child: CustomScrollView(
                    controller: scroll,
                    slivers: <Widget>[
                      const SliverToBoxAdapter(child: SizedBox(height: 1400)),
                      SliverToBoxAdapter(
                        child: TextButton(
                          onPressed: () => taps++,
                          child: const Text('最后一项'),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: StandardBottomInset(
                          key: insetKey,
                          isDesktop: false,
                          navigationVisible: visible,
                          systemBottomInset: safeBottom,
                          keyboardVisible: keyboard > 0,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

    for (final double systemInset in <double>[0, 24, 48]) {
      visible.value = true;
      await show(systemInset);
      await tester.pumpAndSettle();
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      final double visibleHeight =
          MobileFloatingNavBar.bottomOverlayExtent(systemInset) + 8;
      expect(tester.getSize(find.byKey(insetKey)).height, visibleHeight);
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.tap(find.text('最后一项'));

      visible.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(
        tester.getSize(find.byKey(insetKey)).height,
        inExclusiveRange(systemInset + 8, visibleHeight),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byKey(insetKey)).height, systemInset + 8);
      expect(scroll.offset, lessThanOrEqualTo(scroll.position.maxScrollExtent));
      await tester.tap(find.text('最后一项'));
    }
    expect(taps, 6);
    visible.value = true;
    await show(24, keyboard: 240);
    await tester.pumpAndSettle();
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(insetKey)).height, 8);
    await tester.tap(find.text('最后一项'));
    expect(taps, 7);
  });

  testWidgets('桌面末项位于悬浮 Dock 上方，额外间距只有8', (tester) async {
    final ValueNotifier<bool> visible = ValueNotifier<bool>(true);
    final ScrollController scroll = ScrollController();
    addTearDown(visible.dispose);
    addTearDown(scroll.dispose);
    int taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              CustomScrollView(
                controller: scroll,
                slivers: <Widget>[
                  const SliverToBoxAdapter(child: SizedBox(height: 1400)),
                  SliverToBoxAdapter(
                    child: TextButton(
                      onPressed: () => taps++,
                      child: const Text('最后一项'),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: StandardBottomInset(
                      isDesktop: true,
                      navigationVisible: visible,
                      systemBottomInset: 0,
                      keyboardVisible: false,
                    ),
                  ),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Center(
                  child: DesktopDock(
                    selectedIndex: 0,
                    destinations: appDestinations,
                    onDestinationSelected: (_) {},
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(StandardBottomInset)).height, 94);
    final double itemBottom = tester.getBottomLeft(find.byType(TextButton)).dy;
    final double dockTop = tester.getTopLeft(find.byType(DesktopDock)).dy;
    expect(itemBottom, closeTo(dockTop - 8, 0.01));
    await tester.tap(find.text('最后一项'));
    expect(taps, 1);
  });
}
