import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/services/primary_tab_session_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PrimaryTabSessionStore buildStore() {
    return PrimaryTabSessionStore(
      rootUris: <int, Uri>{
        0: Uri.parse('https://example.com/'),
        1: Uri.parse('https://example.com/comics'),
        2: Uri.parse('https://example.com/rank'),
        3: Uri.parse('https://example.com/person/home'),
      },
    );
  }

  test('push and pop keep an independent stack per tab', () {
    final PrimaryTabSessionStore store = buildStore();

    store.push(1, Uri.parse('https://example.com/search?q=robot'));
    store.push(1, Uri.parse('https://example.com/comic/demo'));

    expect(
      store
          .stackForTab(1)
          .map((PrimaryTabRouteEntry entry) => entry.uri)
          .toList(),
      equals(<Uri>[
        Uri.parse('https://example.com/comics'),
        Uri.parse('https://example.com/search?q=robot'),
        Uri.parse('https://example.com/comic/demo'),
      ]),
    );
    expect(store.canPop(1), isTrue);
    expect(store.pop(1)?.uri, Uri.parse('https://example.com/search?q=robot'));
    expect(
      store.currentEntry(1).uri,
      Uri.parse('https://example.com/search?q=robot'),
    );
  });

  test('resetToRoot keeps the cached root entry and drops nested routes', () {
    final PrimaryTabSessionStore store = buildStore();

    store.updatePage(
      1,
      HomePageData(
        title: '发现根页',
        uri: 'https://example.com/comics',
        heroBanners: const <HeroBannerData>[],
        sections: const <ComicSectionData>[],
      ),
    );
    store.updateScroll(1, '/comics', 320);
    store.push(1, Uri.parse('https://example.com/comic/demo'));

    final PrimaryTabRouteEntry entry = store.resetToRoot(1);

    expect(entry.uri, Uri.parse('https://example.com/comics'));
    expect(entry.page, isA<HomePageData>());
    expect(entry.standardScrollOffset, 320);
    expect(store.stackForTab(1), hasLength(1));
  });

  test('replaceCurrent keeps current state while syncing the final uri', () {
    final PrimaryTabSessionStore store = buildStore();

    store.push(1, Uri.parse('https://example.com/search?q=abc'));
    store.updateCurrent(
      1,
      (PrimaryTabRouteEntry entry) => entry.copyWith(
        isLoading: true,
        page: DiscoverPageData(
          title: '搜索',
          uri: 'https://example.com/search?q=abc',
          filters: const <FilterGroupData>[],
          items: const <ComicCardData>[],
          pager: const PagerData(),
          spotlight: const <ComicCardData>[],
        ),
        standardScrollOffset: 180,
      ),
    );

    store.replaceCurrent(
      1,
      Uri.parse('https://example.com/search?q=abc&page=2'),
    );

    final PrimaryTabRouteEntry entry = store.currentEntry(1);
    expect(entry.uri, Uri.parse('https://example.com/search?page=2&q=abc'));
    expect(entry.isLoading, isTrue);
    expect(entry.page, isA<DiscoverPageData>());
    expect(entry.standardScrollOffset, 180);
  });

  test(
    'replaceCurrent keeps discover filter changes on a single stack entry',
    () {
      final PrimaryTabSessionStore store = buildStore();

      store.replaceCurrent(
        1,
        Uri.parse('https://example.com/comics?theme=maoxian'),
      );
      store.replaceCurrent(
        1,
        Uri.parse('https://example.com/comics?theme=qihuan&ordering=-popular'),
      );

      expect(store.stackForTab(1), hasLength(1));
      expect(
        store.currentEntry(1).uri,
        Uri.parse('https://example.com/comics?ordering=-popular&theme=qihuan'),
      );
    },
  );

  test('updateScroll and updateError target the matching route entry only', () {
    final PrimaryTabSessionStore store = buildStore();

    store.push(1, Uri.parse('https://example.com/search?q=robot'));
    store.push(1, Uri.parse('https://example.com/comic/demo'));
    store.updateScroll(1, '/search?q=robot', 240);
    store.updateError(1, '/comic/demo', '加载失败');

    final List<PrimaryTabRouteEntry> entries = store.stackForTab(1);
    expect(entries[1].standardScrollOffset, 240);
    expect(entries[1].errorMessage, isNull);
    expect(entries[2].errorMessage, '加载失败');
  });
}
