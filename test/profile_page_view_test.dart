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

  testWidgets('ProfilePageView renders appearance settings and forwards theme changes', (
    WidgetTester tester,
  ) async {
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
  });

  testWidgets('ProfilePageView keeps cached entry visible when logged out', (
    WidgetTester tester,
  ) async {
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
              afterContinueReading: const Text('已缓存漫画'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('已缓存漫画'), findsOneWidget);
  });

  testWidgets(
    'ProfilePageView renders native profile sections when logged in',
    (WidgetTester tester) async {
      int logoutTaps = 0;
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
                onOpenComic: (_) {},
                onOpenHistory: (ProfileHistoryItem item) {
                  openedHistory = item;
                },
              ),
            ),
          ),
        ),
      );

      expect(find.text('演示用户'), findsOneWidget);
      expect(find.text('继续阅读'), findsOneWidget);
      expect(find.text('我的收藏'), findsOneWidget);
      expect(find.text('浏览历史'), findsOneWidget);

      await tester.ensureVisible(find.text('第3话'));
      await tester.tap(find.text('第3话'));
      await tester.pumpAndSettle();
      expect(openedHistory?.chapterHref, contains('/chapter/3'));

      await tester.ensureVisible(find.byIcon(Icons.logout_rounded));
      await tester.tap(find.byIcon(Icons.logout_rounded));
      await tester.pumpAndSettle();
      expect(logoutTaps, 1);
    },
  );

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
    expect(find.text('beta.example'), findsOneWidget);

    await tester.tap(find.text('管理节点'));
    await tester.pumpAndSettle();

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
  });
}
