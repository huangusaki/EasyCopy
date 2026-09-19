import 'package:flutter_test/flutter_test.dart';
import 'package:reader/config/app_config.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/services/discover_filter_selection.dart';

DiscoverPageData _page() => DiscoverPageData(
  title: '发现',
  uri: 'https://example.com/comics?page=3&offset=40&limit=20',
  filters: const <FilterGroupData>[
    FilterGroupData(
      label: '题材',
      options: <LinkAction>[
        LinkAction(label: '全部', href: '/comics?limit=20', active: true),
        LinkAction(label: '冒险', href: '/comics?theme=adventure&limit=20'),
        LinkAction(label: '查看全部分類', href: '/filter?point=0'),
      ],
    ),
    FilterGroupData(
      label: '地区',
      options: <LinkAction>[
        LinkAction(label: '全部', href: '/comics?limit=20', active: true),
        LinkAction(label: '日本', href: '/comics?region=japan&limit=20'),
      ],
    ),
  ],
  items: const <ComicCardData>[],
  pager: const PagerData(),
  spotlight: const <ComicCardData>[],
);

Uri _select(DiscoverPageData page, Uri currentUri, int group, int option) =>
    resolveDiscoverFilterUri(
      page,
      currentUri: currentUri,
      group: page.filters[group],
      href: page.filters[group].options[option].href,
    );

void main() {
  test('快速跨组筛选合并条件并重置分页，响应 URI 与链接不漂移', () {
    final DiscoverPageData page = _page();
    final Uri themeUri = _select(page, Uri.parse(page.uri), 0, 1);
    final DiscoverPageData themePage = applyDiscoverFilterSelection(
      page,
      currentUri: Uri.parse(page.uri),
      targetUri: themeUri,
    );
    final Uri regionUri = _select(themePage, themeUri, 1, 1);
    final DiscoverPageData selectedPage = applyDiscoverFilterSelection(
      themePage,
      currentUri: themeUri,
      targetUri: regionUri,
    );

    expect(regionUri.queryParameters, <String, String>{
      'theme': 'adventure',
      'region': 'japan',
      'limit': '20',
    });
    expect(selectedPage.filters[0].options[1].active, isTrue);
    expect(selectedPage.filters[1].options[1].active, isTrue);
    expect(selectedPage.uri, page.uri);
    expect(
      selectedPage.filters[1].options[1].href,
      page.filters[1].options[1].href,
    );
  });

  test('相同 href 的全部选项按所属组撤销，重复选择保持同一路由', () {
    final DiscoverPageData page = _page();
    final Uri loadedUri = Uri.parse(page.uri);
    expect(_select(page, loadedUri, 0, 0), loadedUri);
    final Uri themeUri = _select(page, Uri.parse(page.uri), 0, 1);
    final Uri regionUri = _select(page, themeUri, 1, 1);
    final DiscoverPageData selectedPage = applyDiscoverFilterSelection(
      page,
      currentUri: Uri.parse(page.uri),
      targetUri: regionUri,
    );
    final Uri restoredTheme = _select(selectedPage, regionUri, 0, 0);
    expect(restoredTheme.queryParameters, <String, String>{
      'region': 'japan',
      'limit': '20',
    });
    final DiscoverPageData restoredPage = applyDiscoverFilterSelection(
      selectedPage,
      currentUri: regionUri,
      targetUri: restoredTheme,
    );
    expect(restoredPage.filters[0].options[0].active, isTrue);
    expect(restoredPage.filters[1].options[1].active, isTrue);
    final Uri repeated = _select(restoredPage, restoredTheme, 0, 0);
    expect(
      AppConfig.routeKeyForUri(repeated),
      AppConfig.routeKeyForUri(restoredTheme),
    );
    expect(
      identical(
        applyDiscoverFilterSelection(
          restoredPage,
          currentUri: restoredTheme,
          targetUri: repeated,
        ),
        restoredPage,
      ),
      isTrue,
    );
  });

  test('加载中恢复原选项能清除最后一个条件', () {
    final DiscoverPageData page = _page().copyWith(
      uri: 'https://example.com/comics',
    );
    final Uri selected = _select(page, Uri.parse(page.uri), 0, 1);
    final Uri restored = _select(page, selected, 0, 0);
    expect(restored.queryParameters, isEmpty);
    expect(restored.path, '/comics');
  });
}
