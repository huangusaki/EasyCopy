import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/widgets/desktop/desktop_search_field.dart';
import 'package:reader/widgets/mobile_search_field.dart';
import 'package:reader/widgets/search_history_panel.dart';

void main() {
  testWidgets('手机历史不占页面，触摸选择与删除不会被外部点击提前关闭', (tester) async {
    final TextEditingController controller = TextEditingController();
    final FocusNode focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    final List<String> history = <String>['冒险', '日常'];
    final List<String> submitted = <String>[];
    int clears = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: <Widget>[
                    MobileSearchField(
                      controller: controller,
                      focusNode: focus,
                      navigationKey: '/comics',
                      history: List<String>.of(history),
                      onSubmit: submitted.add,
                      onClearQuery: controller.clear,
                      onRemoveHistoryEntry: (term) =>
                          update(() => history.remove(term)),
                      onClearHistory: () => clears++,
                    ),
                    const SizedBox(height: 24),
                    const Text('筛选区'),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    final Offset filterPosition = tester.getTopLeft(find.text('筛选区'));
    expect(find.text('最近搜索'), findsNothing);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.text('最近搜索'), findsOneWidget);
    final Finder historyPanel = find.byType(SearchHistoryPanel);
    expect(historyPanel, findsOneWidget);
    expect(
      find.descendant(of: historyPanel, matching: find.byType(Wrap)),
      findsOneWidget,
    );
    expect(find.byType(ListTile), findsNothing);
    expect(tester.getTopLeft(find.text('筛选区')), filterPosition);
    await tester.tap(find.byTooltip('删除这条历史').first);
    await tester.pumpAndSettle();
    expect(history, <String>['日常']);
    expect(focus.hasFocus, isTrue);
    expect(submitted, isEmpty);
    await tester.tap(find.text('日常'));
    await tester.pumpAndSettle();
    expect(submitted, <String>['日常']);
    expect(focus.hasFocus, isFalse);
    expect(find.text('最近搜索'), findsNothing);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(700, 500));
    await tester.pumpAndSettle();
    expect(find.text('最近搜索'), findsNothing);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('清空历史'));
    await tester.pumpAndSettle();
    expect(clears, 1);
    expect(find.text('最近搜索'), findsNothing);
    update(history.clear);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(find.text('最近搜索'), findsNothing);
  });

  testWidgets('下拉适配小屏键盘，关闭输入法与切页均收起', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 700);
    addTearDown(tester.view.reset);
    final TextEditingController controller = TextEditingController();
    final FocusNode focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    final List<String> history = <String>[
      '这是一条超过小屏幕宽度的搜索历史，需要在胶囊内截断显示，同时仍然保留完整的搜索关键词用于再次提交',
      for (int i = 1; i < 10; i++) '历史$i：在异世界寻找失落王国的冒险故事',
    ];
    final List<String> submitted = <String>[];
    String navigationKey = '/comics';
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 100, 16, 0),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: MobileSearchField(
                    controller: controller,
                    focusNode: focus,
                    navigationKey: navigationKey,
                    history: history,
                    onSubmit: submitted.add,
                    onClearQuery: controller.clear,
                    onRemoveHistoryEntry: (_) {},
                    onClearHistory: () {},
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 350);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final Finder historyPanel = find.byType(SearchHistoryPanel);
    final Finder historyList = find.descendant(
      of: historyPanel,
      matching: find.byType(SingleChildScrollView),
    );
    expect(historyList, findsOneWidget);
    expect(find.text(history.first), findsOneWidget);
    expect(tester.getBottomLeft(historyPanel).dy, lessThanOrEqualTo(342));
    expect(tester.getBottomLeft(historyList).dy, lessThanOrEqualTo(342));
    expect(
      tester.getSize(historyPanel).width,
      tester.getSize(find.byType(MobileSearchField)).width,
    );
    await tester.drag(historyList, const Offset(0, -450));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(history.last).hitTestable(), findsOneWidget);
    await tester.tap(find.text(history.last));
    await tester.pumpAndSettle();
    expect(submitted, <String>[history.last]);
    expect(focus.hasFocus, isFalse);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding();
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isFalse);
    expect(find.text('最近搜索'), findsNothing);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    update(() => navigationKey = '/search?q=新搜索');
    await tester.pumpAndSettle();
    expect(find.text('最近搜索'), findsNothing);
    expect(focus.hasFocus, isFalse);
  });

  testWidgets('桌面鼠标按下历史后仍能完成点击提交', (tester) async {
    final TextEditingController controller = TextEditingController();
    final FocusNode focus = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    final List<String> submitted = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.windows),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: DesktopSearchField(
              controller: controller,
              focusNode: focus,
              history: const <String>['测试历史'],
              onSubmit: submitted.add,
              onRemoveHistoryEntry: (_) {},
              onClearHistory: () {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    final Finder historyPanel = find.byType(SearchHistoryPanel);
    expect(historyPanel, findsOneWidget);
    expect(
      find.descendant(of: historyPanel, matching: find.byType(Wrap)),
      findsOneWidget,
    );
    final TestGesture mouse = await tester.startGesture(
      tester.getCenter(find.text('测试历史')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    expect(find.text('测试历史'), findsOneWidget);
    await mouse.up();
    await tester.pumpAndSettle();
    expect(submitted, <String>['测试历史']);
    expect(focus.hasFocus, isFalse);
  });
}
