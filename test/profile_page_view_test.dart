import 'package:easy_copy/models/page_models.dart';
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
    await tester.tap(find.text('登录 / 注册'));
    await tester.pump();
    expect(authTaps, 1);
  });

  testWidgets('ProfilePageView renders native profile sections when logged in', (
    WidgetTester tester,
  ) async {
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
  });
}
