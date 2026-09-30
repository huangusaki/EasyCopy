import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/models/blocked_content.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/services/blocked_content_filter.dart';
import 'package:reader/services/blocked_content_store.dart';
import 'package:reader/services/local_library_store.dart';
import 'package:reader/services/navigation_request_guard.dart';
import 'package:reader/services/page_cache_store.dart';
import 'package:reader/services/page_repository.dart';
import 'package:reader/services/site_html_page_parser.dart';
import 'package:reader/services/site_page_source.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory directory;
  late LocalLibraryStore libraryStore;
  late BlockedContentStore blockedStore;

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('easy-copy-blocked-');
    libraryStore = LocalLibraryStore(
      directoryProvider: () async => directory,
      databaseFactory: databaseFactoryFfi,
    );
    blockedStore = BlockedContentStore(libraryStore: libraryStore);
    await blockedStore.ensureInitialized();
  });

  tearDown(() async {
    await libraryStore.close();
    await directory.delete(recursive: true);
  });

  test('屏蔽规则持久化、去重并可解除', () async {
    await blockedStore.blockComic(
      href: 'https://example.com/comic/demo',
      title: '测试漫画',
    );
    await blockedStore.blockComic(href: '/comic/demo', title: '测试漫画（更新）');
    await blockedStore.blockAuthor(label: '作者甲', href: '/author/a');

    expect(blockedStore.items, hasLength(2));
    expect(blockedStore.itemsOfType(BlockedContentType.comic), hasLength(1));
    expect(blockedStore.itemsOfType(BlockedContentType.author), hasLength(1));

    await libraryStore.close();
    await blockedStore.ensureInitialized();
    expect(blockedStore.items, hasLength(2));

    await blockedStore.unblock(
      blockedStore.items.firstWhere(
        (BlockedContentItem item) => item.type == BlockedContentType.comic,
      ),
    );
    expect(blockedStore.itemsOfType(BlockedContentType.comic), isEmpty);
  });

  test('首页和排行过滤漫画与作者，详情和个人页保持不变', () async {
    await blockedStore.blockComic(href: '/comic/hidden', title: '隐藏漫画');
    await blockedStore.blockAuthor(label: '作者甲', href: '/author/a');
    final BlockedContentFilter filter = BlockedContentFilter(blockedStore);

    const ComicCardData visible = ComicCardData(
      title: '可见',
      coverUrl: '',
      href: '/comic/visible',
      subtitle: '作者：作者乙',
    );
    const ComicCardData hiddenByAuthor = ComicCardData(
      title: '作者命中',
      coverUrl: '',
      href: '/comic/author-hidden',
      authorLinks: <LinkAction>[LinkAction(label: '作者甲', href: '/author/a')],
    );
    const ComicCardData hiddenByComic = ComicCardData(
      title: '漫画命中',
      coverUrl: '',
      href: '/comic/hidden',
    );
    final HomePageData home = HomePageData(
      title: '首页',
      uri: 'https://example.com/',
      heroBanners: const <HeroBannerData>[],
      sections: <ComicSectionData>[
        const ComicSectionData(
          title: '推荐',
          items: <ComicCardData>[visible, hiddenByAuthor, hiddenByComic],
        ),
      ],
    );
    final SitePage filteredHome = filter.apply(home);
    expect(
      (filteredHome as HomePageData).sections.single.items,
      <ComicCardData>[visible],
    );

    final RankPageData rank = RankPageData(
      title: '排行',
      uri: 'https://example.com/rank',
      categories: const <LinkAction>[],
      periods: const <LinkAction>[],
      items: const <RankEntryData>[
        RankEntryData(
          rankLabel: '1',
          title: '作者命中',
          coverUrl: '',
          href: '/comic/rank-hidden',
          authors: '作者甲',
        ),
      ],
    );
    expect((filter.apply(rank) as RankPageData).items, isEmpty);

    final DetailPageData detail = DetailPageData(
      title: '隐藏漫画',
      uri: 'https://example.com/comic/hidden',
      coverUrl: '',
      aliases: '',
      authors: '',
      updatedAt: '',
      status: '',
      summary: '',
      tags: const <LinkAction>[],
      startReadingHref: '',
      chapterGroups: const <ChapterGroupData>[],
      chapters: const <ChapterData>[],
    );
    expect(identical(filter.apply(detail), detail), isTrue);
    final ProfilePageData profile = ProfilePageData.loggedOut(
      uri: 'https://example.com/person',
    );
    expect(identical(filter.apply(profile), profile), isTrue);
  });

  test('作者链接优先，缺少链接才按名称匹配，文字不覆盖链接身份', () async {
    await blockedStore.blockAuthor(label: '同名作者', href: '/author/a');
    final DiscoverPageData page = DiscoverPageData(
      title: '发现',
      uri: 'https://example.com/comics',
      filters: const [],
      pager: const PagerData(),
      spotlight: const [],
      items: const [
        ComicCardData(
          title: '同一作者改名',
          coverUrl: '',
          href: '/comic/a',
          authorLinks: [
            LinkAction(label: '新名字', href: 'https://example.com/author/a'),
          ],
        ),
        ComicCardData(
          title: '同名其他作者',
          coverUrl: '',
          href: '/comic/b',
          subtitle: '作者：同名作者',
          authorLinks: [LinkAction(label: '同名作者', href: '/author/b')],
        ),
        ComicCardData(
          title: '仅有名字',
          coverUrl: '',
          href: '/comic/c',
          subtitle: '作者：同名作者 / 其他作者',
        ),
      ],
    );
    final BlockedContentFilter filter = BlockedContentFilter(blockedStore);
    expect((filter.apply(page) as DiscoverPageData).items.map((e) => e.href), [
      '/comic/b',
    ]);
    await blockedStore.unblock(blockedStore.items.single);
    await blockedStore.blockAuthor(label: '同名作者');
    expect((filter.apply(page) as DiscoverPageData).items.map((e) => e.href), [
      '/comic/a',
    ]);
    expect(page.items.last.resolvedAuthors.map((e) => e.label), [
      '同名作者',
      '其他作者',
    ]);
    expect(authorLinksFromText('作者：--'), isEmpty);
  });

  test('规则变化无需清缓存，内存及磁盘原始页面均可解除恢复', () async {
    final DiscoverPageData rawPage = DiscoverPageData(
      title: '发现',
      uri: 'https://example.com/comics',
      filters: const [],
      pager: const PagerData(nextHref: '/comics?page=2'),
      spotlight: const [],
      items: const [
        ComicCardData(title: '测试', coverUrl: '', href: '/comic/demo'),
      ],
    );
    final _StaticPageSource source = _StaticPageSource(rawPage);
    final PageRepository repository = PageRepository(
      source: source,
      blockedContentStore: blockedStore,
      cacheStore: PageCacheStore(directoryProvider: () async => directory),
    );
    final Uri uri = Uri.parse(rawPage.uri);
    final PageQueryKey key = PageQueryKey.forUri(uri, authScope: 'guest');
    expect(
      identical(await repository.loadFresh(uri, authScope: 'guest'), rawPage),
      isTrue,
    );
    await blockedStore.blockComic(href: '/comic/demo', title: '测试');
    final CachedPageHit blocked = (await repository.readCached(key))!;
    expect(blocked.fromMemory, isTrue);
    expect((blocked.page as DiscoverPageData).items, isEmpty);
    expect((blocked.page as DiscoverPageData).pager.hasNext, isTrue);
    await blockedStore.unblock(blockedStore.items.single);
    expect(
      ((await repository.readCached(key))!.page as DiscoverPageData).items,
      hasLength(1),
    );
    final PageRepository reopened = PageRepository(
      source: source,
      blockedContentStore: blockedStore,
      cacheStore: PageCacheStore(directoryProvider: () async => directory),
    );
    final CachedPageHit disk = (await reopened.readCached(key))!;
    expect(disk.fromMemory, isFalse);
    expect((disk.page as DiscoverPageData).items, hasLength(1));
    expect(source.loads, 1);
  });

  test('HTML 卡片提取作者链接', () async {
    final SitePage page = await SiteHtmlPageParser.instance.parsePage(
      Uri.parse('https://example.com/comics'),
      '''
      <div class="exemptComicList">
        <div class="exemptComic-box">
          <div class="exemptComic_Item">
            <a href="/comic/demo"><img src="/demo.jpg"></a>
            <div class="exemptComicItem-txt">
              <a href="/comic/demo"><p class="twoLines" title="测试漫画">测试漫画</p></a>
              <span class="exemptComicItem-txt-span">作者：
                <a href="/author/a">作者甲</a>
              </span>
            </div>
          </div>
        </div>
      </div>
      ''',
    );

    expect(page, isA<DiscoverPageData>());
    final ComicCardData item = (page as DiscoverPageData).items.single;
    expect(item.authorLinks.single.label, '作者甲');
    expect(item.authorLinks.single.href, 'https://example.com/author/a');
  });
}

class _StaticPageSource implements SitePageSource {
  _StaticPageSource(this.page);
  final SitePage page;
  int loads = 0;

  @override
  Future<SitePage> load(
    Uri uri, {
    required String authScope,
    NavigationRequestContext? requestContext,
  }) async {
    loads += 1;
    return page;
  }
}
