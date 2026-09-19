import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/app_screen/route_utils.dart';
import 'package:reader/services/navigation_request_guard.dart';
import 'package:reader/services/primary_tab_session_store.dart';
import 'package:reader/widgets/discover_results_sliver.dart';
import 'package:reader/widgets/motion.dart';
import 'package:reader/widgets/page_skeleton.dart';

void main() {
  testWidgets('筛选与分页只让结果淡入，错误可重试且不展示旧结果', (tester) async {
    int retries = 0;
    Future<void> show(String query, {bool loading = false, String? error}) {
      final Uri uri = Uri.parse('https://example.com/comics?$query');
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContentSwitchTransition(
              contentKey: standardPageTransitionKey(
                uri: uri,
                tabIndex: 1,
                routeDepth: 1,
              ),
              tabIndex: 1,
              routeDepth: 1,
              child: CustomScrollView(
                slivers: <Widget>[
                  const SliverToBoxAdapter(child: Text('筛选区')),
                  DiscoverResultsSliver(
                    resultKey: uri.toString(),
                    isLoading: loading,
                    errorMessage: error,
                    onRetry: () => retries++,
                    sliver: const SliverToBoxAdapter(child: Text('漫画结果')),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    double pageOpacity() => tester
        .widget<FadeTransition>(
          find
              .descendant(
                of: find.byType(ContentSwitchTransition),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity
        .value;

    await show('theme=a');
    await tester.pumpAndSettle();
    final Element filters = tester.element(find.text('筛选区'));
    await show('theme=b', loading: true);
    expect(pageOpacity(), 1);
    expect(tester.element(find.text('筛选区')), same(filters));
    expect(find.byType(PageSkeleton), findsOneWidget);
    expect(find.text('漫画结果'), findsNothing);

    await show('theme=b', error: 'network failure');
    expect(find.text('漫画结果'), findsNothing);
    await tester.tap(find.text('重试'));
    expect(retries, 1);
    await show('theme=b', loading: true);
    await show('theme=b');
    final Animation<double> opacity = tester
        .widget<SliverFadeTransition>(find.byType(SliverFadeTransition))
        .opacity;
    expect(opacity.value, 0);
    await tester.pump(const Duration(milliseconds: 100));
    expect(opacity.value, inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(opacity.value, 1);
    expect(pageOpacity(), 1);

    // 缓存命中直接换结果，也只能触发局部动画。
    await show('theme=b&offset=50');
    expect(pageOpacity(), 1);
    expect(opacity.value, 0);
    await tester.pumpAndSettle();
    expect(
      standardPageTransitionKey(
        uri: Uri.parse('https://example.com/search?q=a'),
        tabIndex: 1,
        routeDepth: 2,
      ),
      isNot(
        standardPageTransitionKey(
          uri: Uri.parse('https://example.com/search?q=b'),
          tabIndex: 1,
          routeDepth: 3,
        ),
      ),
    );
  });

  test('后发筛选取得页面归属，迟到响应和离页响应均不得提交', () {
    final Uri uri = Uri.parse('https://example.com/comics?theme=b');
    final PrimaryTabRouteEntry entry = PrimaryTabRouteEntry.root(
      uri,
    ).copyWith(activeRequestId: 2);
    final NavigationRequestContext oldRequest = NavigationRequestContext(
      requestId: 1,
      targetTabIndex: 1,
      routeKey: entry.routeKey,
      intent: NavigationIntent.preserve,
      preserveVisiblePage: true,
      sourceKind: NavigationRequestSourceKind.navigation,
    );
    expect(
      canCommitNavigationRequest(
        currentSelectedIndex: 1,
        currentEntry: entry,
        request: oldRequest,
      ),
      isFalse,
    );
    expect(
      canCommitNavigationRequest(
        currentSelectedIndex: 1,
        currentEntry: entry,
        request: oldRequest.copyWith(requestId: 2),
      ),
      isTrue,
    );
    expect(
      canCommitNavigationRequest(
        currentSelectedIndex: 0,
        currentEntry: entry,
        request: oldRequest.copyWith(requestId: 2),
      ),
      isFalse,
    );
  });
}
