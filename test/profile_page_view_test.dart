import 'package:easy_copy/config/app_config.dart';
import 'package:easy_copy/models/app_preferences.dart';
import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/services/host_manager.dart';
import 'package:easy_copy/widgets/profile_page_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ProfilePageView shows login CTA when logged out', (
    WidgetTester tester,
  ) async {
    int authTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfilePageView(
              page: ProfilePageData.loggedOut(
                uri: 'https://www.2026copy.com/person/home',
              ),
              onAuthenticate: () {
                authTaps += 1;
              },
              onLogout: () {},
              onOpenComic: (_) {},
              onOpenHistory: (_) {},
              onOpenCollections: () {},
              onOpenHistoryPage: () {},
              onOpenCachedComicPage: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('登录 / 注册'), findsOneWidget);
    expect(find.text('外观'), findsOneWidget);
    await tester.tap(find.text('登录 / 注册'));
    await tester.pump();
    expect(authTaps, 1);
  });

  testWidgets(
    'ProfilePageView renders appearance settings and forwards theme changes',
    (WidgetTester tester) async {
      AppThemePreference? selectedTheme;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProfilePageView(
                page: ProfilePageData.loggedOut(
                  uri: 'https://www.2026copy.com/person/home',
                ),
                onAuthenticate: () {},
                onLogout: () {},
                onOpenComic: (_) {},
                onOpenHistory: (_) {},
                onOpenCollections: () {},
                onOpenHistoryPage: () {},
                onOpenCachedComicPage: () {},
                themePreference: AppThemePreference.system,
                onThemePreferenceChanged: (AppThemePreference value) {
                  selectedTheme = value;
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('外观'), findsOneWidget);
      expect(find.text('跟随系统'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('深色').last);
      await tester.pumpAndSettle();

      expect(selectedTheme, AppThemePreference.dark);
    },
  );

  testWidgets(
    'ProfilePageView keeps download management entry visible when logged out',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProfilePageView(
                page: ProfilePageData.loggedOut(
                  uri: 'https://www.2026copy.com/person/home',
                ),
                onAuthenticate: () {},
                onLogout: () {},
                onOpenComic: (_) {},
                onOpenHistory: (_) {},
                onOpenCollections: () {},
                onOpenHistoryPage: () {},
                onOpenCachedComicPage: () {},
                afterContinueReading: const Text('下载管理'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('下载管理'), findsOneWidget);
    },
  );

  testWidgets('ProfilePageView renders cached comics as a separate section', (
    WidgetTester tester,
  ) async {
    String? openedCachedComic;
    String? deletedCachedComic;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfilePageView(
              page: ProfilePageData.loggedOut(
                uri: 'https://www.2026copy.com/person/home',
              ),
              onAuthenticate: () {},
              onLogout: () {},
              onOpenComic: (_) {},
              onOpenHistory: (_) {},
              onOpenCollections: () {},
              onOpenHistoryPage: () {},
              onOpenCachedComicPage: () {},
              onOpenCachedComic: (String href) {
                openedCachedComic = href;
              },
              onDeleteCachedComic: (String href) {
                deletedCachedComic = href;
              },
              cachedComicCards: const <ComicCardData>[
                ComicCardData(
                  title: '缓存作品',
                  subtitle: '12话',
                  secondaryText: '最近缓存：第12话',
                  coverUrl: '',
                  href: 'https://www.2026copy.com/comic/cached',
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('已缓存漫画'), findsOneWidget);
    expect(find.text('缓存作品'), findsOneWidget);

    await tester.ensureVisible(find.text('缓存作品'));
    await tester.tap(find.text('缓存作品'));
    await tester.pumpAndSettle();
    expect(openedCachedComic, 'https://www.2026copy.com/comic/cached');

    await tester.ensureVisible(find.text('缓存作品'));
    await tester.longPress(find.text('缓存作品'));
    await tester.pumpAndSettle();
    expect(deletedCachedComic, 'https://www.2026copy.com/comic/cached');
  });

  testWidgets(
    'ProfilePageView forwards cached section action to the cached subview callback',
    (WidgetTester tester) async {
      String? openedPreviewComic;
      int openedCachedPage = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProfilePageView(
                page: ProfilePageData.loggedOut(
                  uri: 'https://www.2026copy.com/person/home',
                ),
                onAuthenticate: () {},
                onLogout: () {},
                onOpenComic: (_) {},
                onOpenHistory: (_) {},
                onOpenCollections: () {},
                onOpenHistoryPage: () {},
                onOpenCachedComicPage: () {
                  openedCachedPage += 1;
                },
                onOpenCachedComic: (String href) {
                  openedPreviewComic = href;
                },
                cachedComicCards: const <ComicCardData>[
                  ComicCardData(
                    title: '缓存作品',
                    subtitle: '12话',
                    secondaryText: '最近缓存：第12话',
                    coverUrl: '',
                    href: 'https://www.2026copy.com/comic/cached',
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.ensureVisible(find.text('缓存作品'));
      await tester.tap(find.text('缓存作品'));
      await tester.pumpAndSettle();
      expect(openedPreviewComic, 'https://www.2026copy.com/comic/cached');
      expect(openedCachedPage, 0);

      await tester.tap(find.bySemanticsLabel('查看全部缓存'));
      await tester.pump();
      expect(openedCachedPage, 1);
    },
  );

  testWidgets(
    'ProfilePageView renders native profile sections when logged in',
    (WidgetTester tester) async {
      int logoutTaps = 0;
      int openedCollections = 0;
      int openedHistoryPage = 0;
      String? openedComic;
      ProfileHistoryItem? openedHistory;

      final ProfilePageData page = ProfilePageData(
        title: '我的',
        uri: 'https://www.2026copy.com/person/home',
        isLoggedIn: true,
        user: const ProfileUserData(
          userId: '42',
          username: 'demo_user',
          nickname: '演示用户',
          createdAt: '2026-03-01',
          membershipLabel: 'VIP',
        ),
        continueReading: const ProfileHistoryItem(
          title: '示例漫画',
          coverUrl: '',
          comicHref: 'https://www.2026copy.com/comic/demo',
          chapterLabel: '第10话',
          chapterHref: 'https://www.2026copy.com/comic/demo/chapter/10',
        ),
        collections: const <ProfileLibraryItem>[
          ProfileLibraryItem(
            title: '收藏作品',
            coverUrl: '',
            href: 'https://www.2026copy.com/comic/favorite',
          ),
        ],
        history: const <ProfileHistoryItem>[
          ProfileHistoryItem(
            title: '最近阅读',
            coverUrl: '',
            comicHref: 'https://www.2026copy.com/comic/recent',
            chapterLabel: '第3话',
            chapterHref: 'https://www.2026copy.com/comic/recent/chapter/3',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ProfilePageView(
                page: page,
                onAuthenticate: () {},
                onLogout: () {
                  logoutTaps += 1;
                },
                onOpenComic: (String href) {
                  openedComic = href;
                },
                onOpenHistory: (ProfileHistoryItem item) {
                  openedHistory = item;
                },
                onOpenCollections: () {
                  openedCollections += 1;
                },
                onOpenHistoryPage: () {
                  openedHistoryPage += 1;
                },
                onOpenCachedComicPage: () {},
              ),
            ),
          ),
        ),
      );

      final SemanticsHandle semantics = tester.ensureSemantics();
      expect(find.text('演示用户'), findsOneWidget);
      expect(find.text('继续阅读'), findsOneWidget);
      expect(find.text('我的收藏'), findsOneWidget);
      expect(find.text('浏览历史'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('查看全部收藏'));
      await tester.pumpAndSettle();
      expect(openedCollections, 1);

      await tester.ensureVisible(find.bySemanticsLabel('查看全部历史'));
      await tester.tap(find.bySemanticsLabel('查看全部历史'));
      await tester.pumpAndSettle();
      expect(openedHistoryPage, 1);

      await tester.ensureVisible(find.text('第10话'));
      await tester.tap(find.text('第10话'));
      await tester.pumpAndSettle();
      expect(openedHistory?.chapterHref, contains('/chapter/10'));

      await tester.ensureVisible(find.text('第3话'));
      await tester.tap(find.text('第3话'));
      await tester.pumpAndSettle();
      expect(openedComic, contains('/comic/recent'));

      await tester.ensureVisible(find.byIcon(Icons.logout_rounded));
      await tester.tap(find.byIcon(Icons.logout_rounded));
      await tester.pumpAndSettle();
      expect(logoutTaps, 1);
      semantics.dispose();
    },
  );

  testWidgets('ProfilePageView renders collections subview in place', (
    WidgetTester tester,
  ) async {
    String? openedComic;

    final ProfilePageData page = ProfilePageData(
      title: '我的',
      uri: 'https://www.2026copy.com/person/home?view=collections',
      isLoggedIn: true,
      user: const ProfileUserData(userId: '42', username: 'demo_user'),
      collections: const <ProfileLibraryItem>[
        ProfileLibraryItem(
          title: '收藏作品',
          coverUrl: '',
          href: 'https://www.2026copy.com/comic/favorite',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfilePageView(
              page: page,
              activeSubview: ProfileSubview.collections,
              onAuthenticate: () {},
              onLogout: () {},
              onOpenComic: (String href) {
                openedComic = href;
              },
              onOpenHistory: (_) {},
              onOpenCollections: () {},
              onOpenHistoryPage: () {},
              onOpenCachedComicPage: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('我的收藏'), findsOneWidget);
    expect(find.text('共 1 部漫画'), findsOneWidget);
    expect(find.text('收藏作品'), findsOneWidget);
    expect(find.text('继续阅读'), findsNothing);
    await tester.tap(find.text('收藏作品'));
    await tester.pumpAndSettle();
    expect(openedComic, 'https://www.2026copy.com/comic/favorite');
  });

  testWidgets('ProfilePageView renders history subview in place', (
    WidgetTester tester,
  ) async {
    String? openedComic;

    final ProfilePageData page = ProfilePageData(
      title: '我的',
      uri: 'https://www.2026copy.com/person/home?view=history',
      isLoggedIn: true,
      user: const ProfileUserData(userId: '42', username: 'demo_user'),
      history: const <ProfileHistoryItem>[
        ProfileHistoryItem(
          title: '最近阅读',
          coverUrl: '',
          comicHref: 'https://www.2026copy.com/comic/recent',
          chapterLabel: '第3话',
          chapterHref: 'https://www.2026copy.com/comic/recent/chapter/3',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfilePageView(
              page: page,
              activeSubview: ProfileSubview.history,
              onAuthenticate: () {},
              onLogout: () {},
              onOpenComic: (String href) {
                openedComic = href;
              },
              onOpenHistory: (_) {},
              onOpenCollections: () {},
              onOpenHistoryPage: () {},
              onOpenCachedComicPage: () {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('浏览历史'), findsOneWidget);
    expect(find.text('共 1 条记录'), findsOneWidget);
    expect(find.text('最近阅读'), findsOneWidget);
    expect(find.text('我的收藏'), findsNothing);
    await tester.tap(find.text('最近阅读'));
    await tester.pumpAndSettle();
    expect(openedComic, 'https://www.2026copy.com/comic/recent');
  });

  testWidgets('ProfilePageView renders cached subview in place', (
    WidgetTester tester,
  ) async {
    String? openedCachedComic;
    String? deletedCachedComic;

    final ProfilePageData page = ProfilePageData.loggedOut(
      uri: 'https://www.2026copy.com/person/home?view=cached',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfilePageView(
              page: page,
              activeSubview: ProfileSubview.cached,
              onAuthenticate: () {},
              onLogout: () {},
              onOpenComic: (_) {},
              onOpenHistory: (_) {},
              onOpenCollections: () {},
              onOpenHistoryPage: () {},
              onOpenCachedComicPage: () {},
              onOpenCachedComic: (String href) {
                openedCachedComic = href;
              },
              onDeleteCachedComic: (String href) {
                deletedCachedComic = href;
              },
              cachedComicCards: const <ComicCardData>[
                ComicCardData(
                  title: '缓存作品',
                  subtitle: '12话',
                  secondaryText: '最近缓存：第12话',
                  coverUrl: '',
                  href: 'https://www.2026copy.com/comic/cached',
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('已缓存漫画'), findsOneWidget);
    expect(find.text('共 1 部漫画'), findsOneWidget);
    expect(find.text('缓存作品'), findsOneWidget);
    expect(find.text('外观'), findsNothing);

    await tester.tap(find.text('缓存作品'));
    await tester.pumpAndSettle();
    expect(openedCachedComic, 'https://www.2026copy.com/comic/cached');

    await tester.longPress(find.text('缓存作品'));
    await tester.pumpAndSettle();
    expect(deletedCachedComic, 'https://www.2026copy.com/comic/cached');
  });

  testWidgets('ProfilePageView renders host settings and forwards actions', (
    WidgetTester tester,
  ) async {
    int refreshTaps = 0;
    int autoSelectionTaps = 0;
    String? selectedHost;

    final ProfilePageData page = ProfilePageData.loggedOut(
      uri: 'https://www.2026copy.com/person/home',
    );
    final HostProbeSnapshot snapshot = HostProbeSnapshot(
      selectedHost: 'alpha.example',
      checkedAt: DateTime(2026, 3, 7, 9, 30),
      sessionPinnedHost: 'beta.example',
      probes: const <HostProbeRecord>[
        HostProbeRecord(
          host: 'alpha.example',
          success: true,
          latencyMs: 48,
          statusCode: 200,
        ),
        HostProbeRecord(
          host: 'beta.example',
          success: true,
          latencyMs: 70,
          statusCode: 200,
        ),
        HostProbeRecord(
          host: 'gamma.example',
          success: false,
          latencyMs: 999999,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfilePageView(
              page: page,
              onAuthenticate: () {},
              onLogout: () {},
              onOpenComic: (_) {},
              onOpenHistory: (_) {},
              onOpenCollections: () {},
              onOpenHistoryPage: () {},
              onOpenCachedComicPage: () {},
              currentHost: 'beta.example',
              candidateHosts: const <String>[
                'alpha.example',
                'beta.example',
                'gamma.example',
              ],
              hostSnapshot: snapshot,
              onRefreshHosts: () {
                refreshTaps += 1;
              },
              onUseAutomaticHostSelection: () {
                autoSelectionTaps += 1;
              },
              onSelectHost: (String host) {
                selectedHost = host;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('节点设置'), findsOneWidget);
    expect(find.text('管理节点'), findsOneWidget);
    expect(find.text('beta.example'), findsNothing);

    await tester.tap(find.text('管理节点'));
    await tester.pumpAndSettle();

    expect(find.text('当前已手动锁定到 beta.example。点击其他节点可立即切换。'), findsOneWidget);
    expect(find.text('恢复自动选择'), findsOneWidget);
    expect(find.text('推荐'), findsOneWidget);
    expect(find.text('gamma.example'), findsOneWidget);

    await tester.tap(find.text('重新测速'));
    await tester.pumpAndSettle();
    expect(refreshTaps, 1);

    await tester.tap(find.text('恢复自动选择'));
    await tester.pumpAndSettle();
    expect(autoSelectionTaps, 1);

    await tester.ensureVisible(find.text('gamma.example'));
    await tester.tap(find.text('gamma.example'));
    await tester.pumpAndSettle();
    expect(selectedHost, 'gamma.example');
    expect(find.text('当前已手动锁定到 gamma.example。点击其他节点可立即切换。'), findsOneWidget);
  });
}
