import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/app_screen/route_utils.dart';
import 'package:reader/config/app_config.dart';
import 'package:reader/models/blocked_content.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/services/local_library_store.dart';
import 'package:reader/services/local_profile_page_loader.dart';
import 'package:reader/services/site_api_client.dart';
import 'package:reader/services/site_session.dart';
import 'package:reader/widgets/profile_page_view.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _LocalSession extends SiteSession {
  @override
  Future<void> ensureInitialized() async {}
}

class _NoRemoteProfile extends SiteApiClient {
  @override
  Future<ProfilePageData> loadProfile({Uri? uri}) async {
    throw StateError('屏蔽列表不应请求服务器');
  }
}

void main() {
  late Directory directory;
  late LocalLibraryStore store;
  late LocalProfilePageLoader loader;
  final Uri blockedUri = AppConfig.buildProfileUri(
    view: ProfileSubview.blocked,
  );

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'easy-copy-blocked-page-',
    );
    store = LocalLibraryStore(
      directoryProvider: () async => directory,
      databaseFactory: databaseFactoryFfi,
    );
    loader = LocalProfilePageLoader(
      libraryStore: store,
      session: _LocalSession(),
      apiClient: _NoRemoteProfile(),
    );
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test('屏蔽规则分页且删除末页唯一项后回到有效页', () async {
    for (int index = 0; index < 21; index += 1) {
      await store.upsertBlocked(
        BlockedContentItem(
          type: BlockedContentType.comic,
          key: '/comic/$index',
          label: '漫画$index',
          addedAtMs: index + 1,
        ),
      );
    }
    final first = await store.readBlockedPage(page: 1);
    final second = await store.readBlockedPage(page: 2);
    expect(first.items, hasLength(20));
    expect(first.total, 21);
    expect(second.items.single.key, '/comic/0');
    expect(second.page, 2);
    expect(store.blockedItems, hasLength(21));

    final Uri lastPageUri = AppConfig.buildProfileUri(
      view: ProfileSubview.blocked,
      page: 2,
    );
    final ProfilePageData lastPage = await loader.loadLocalProfile(
      lastPageUri,
      authScope: LocalLibraryStore.guestScope,
    );
    expect(lastPage.blockedPager.currentPageNumber, 2);
    expect(lastPage.blockedPager.totalPageCount, 2);
    expect(lastPage.blockedItems, hasLength(1));

    await store.removeBlocked(BlockedContentType.comic, '/comic/0');
    final ProfilePageData refreshed = await loader.loadLocalProfile(
      lastPageUri,
      authScope: LocalLibraryStore.guestScope,
    );
    expect(refreshed.blockedItems, hasLength(20));
    expect(refreshed.blockedPager.currentPageNumber, 1);
    expect(refreshed.blockedPager.hasNext, isFalse);
    expect(AppConfig.profilePageForUri(Uri.parse(refreshed.uri)), 1);
  });

  test('切回屏蔽页重新读取规则，游客与不同账号共享本地数据', () async {
    final ProfilePageData oldPage = await loader.loadProfile(
      blockedUri,
      authScope: LocalLibraryStore.guestScope,
    );
    expect(oldPage.blockedItems, isEmpty);
    await store.upsertBlocked(
      const BlockedContentItem(
        type: BlockedContentType.author,
        key: '/author/a',
        label: '作者甲',
      ),
    );

    for (final String scope in <String>['guest', 'user:a', 'user:b']) {
      expect(
        profileNeedsRefresh(
          uri: blockedUri,
          page: oldPage,
          isAuthenticated: scope != 'guest',
        ),
        isTrue,
      );
      final ProfilePageData refreshed = await loader.loadProfile(
        blockedUri,
        authScope: scope,
      );
      expect(refreshed.blockedItems.single.label, '作者甲');
    }
  });

  testWidgets('屏蔽页分组显示并传递翻页和解除操作', (WidgetTester tester) async {
    const BlockedContentItem comic = BlockedContentItem(
      type: BlockedContentType.comic,
      key: '/comic/a',
      label: '漫画甲',
    );
    const BlockedContentItem author = BlockedContentItem(
      type: BlockedContentType.author,
      key: '/author/a',
      label: '作者甲',
    );
    int? selectedPage;
    BlockedContentItem? removed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfilePageView(
              page: ProfilePageData(
                title: '已屏蔽',
                uri: blockedUri.toString(),
                isLoggedIn: false,
                blockedItems: const <BlockedContentItem>[comic, author],
                blockedPager: const PagerData(
                  currentLabel: '1',
                  totalLabel: '共2页 · 21条',
                  nextHref: '?view=blocked&page=2',
                ),
              ),
              activeSubview: ProfileSubview.blocked,
              onAuthenticate: () {},
              onLogout: () {},
              onOpenComic: (_) {},
              onOpenHistory: (_) {},
              onOpenCollections: () {},
              onOpenHistoryPage: () {},
              onOpenCachedComicPage: () {},
              onOpenBlockedPage: () {},
              onOpenBlockedPageNumber: (int page) => selectedPage = page,
              onRemoveBlocked: (BlockedContentItem item) => removed = item,
            ),
          ),
        ),
      ),
    );
    expect(find.text('漫画'), findsOneWidget);
    expect(find.text('作者'), findsOneWidget);
    await tester.tap(find.byTooltip('解除屏蔽').first);
    expect(removed, comic);
    await tester.tap(find.text('下一页'));
    expect(selectedPage, 2);
    expect(tester.takeException(), isNull);
  });
}
