import 'package:easy_copy/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolvePath builds URLs against the new domain', () {
    expect(
      AppConfig.resolvePath('/rank').toString(),
      'https://www.2026copy.com/rank',
    );
  });

  test('profile subview helpers build and parse internal profile routes', () {
    expect(
      AppConfig.buildProfileUri().toString(),
      'https://www.2026copy.com/person/home',
    );
    expect(
      AppConfig.buildProfileUri(view: ProfileSubview.collections).toString(),
      'https://www.2026copy.com/person/home?view=collections',
    );
    expect(
      AppConfig.buildProfileUri(view: ProfileSubview.history).toString(),
      'https://www.2026copy.com/person/home?view=history',
    );
    expect(
      AppConfig.buildProfileUri(view: ProfileSubview.cached).toString(),
      'https://www.2026copy.com/person/home?view=cached',
    );
    expect(
      AppConfig.profileSubviewForUri(
        Uri.parse('https://www.2026copy.com/person/home?view=collections'),
      ),
      ProfileSubview.collections,
    );
    expect(
      AppConfig.profileSubviewForUri(
        Uri.parse('https://www.2026copy.com/person/home?view=history'),
      ),
      ProfileSubview.history,
    );
    expect(
      AppConfig.profileSubviewForUri(
        Uri.parse('https://www.2026copy.com/person/home?view=cached'),
      ),
      ProfileSubview.cached,
    );
    expect(
      AppConfig.profileSubviewForUri(
        Uri.parse('https://www.2026copy.com/person/home?view=unknown'),
      ),
      ProfileSubview.root,
    );
    expect(AppConfig.profileSubviewTitle(ProfileSubview.collections), '我的收藏');
    expect(AppConfig.profileSubviewTitle(ProfileSubview.cached), '已缓存漫画');
  });

  test('isAllowedNavigationUri blocks external domains and schemes', () {
    expect(
      AppConfig.isAllowedNavigationUri(
        Uri.parse('https://www.2026copy.com/comics'),
      ),
      isTrue,
    );
    expect(
      AppConfig.isAllowedNavigationUri(Uri.parse('https://example.com')),
      isFalse,
    );
    expect(
      AppConfig.isAllowedNavigationUri(Uri.parse('mailto:test@example.com')),
      isFalse,
    );
    expect(AppConfig.isAllowedNavigationUri(Uri.parse('about:blank')), isTrue);
  });

  test('tabIndexForUri keeps major site areas mapped to navigation tabs', () {
    expect(tabIndexForUri(Uri.parse('https://www.2026copy.com/')), 0);
    expect(tabIndexForUri(Uri.parse('https://www.2026copy.com/comic/demo')), 1);
    expect(tabIndexForUri(Uri.parse('https://www.2026copy.com/rank/day')), 2);
    expect(
      tabIndexForUri(
        Uri.parse('https://www.2026copy.com/person/home?view=history'),
      ),
      3,
    );
    expect(
      tabIndexForUri(
        Uri.parse('https://www.2026copy.com/web/login?url=person/home'),
      ),
      3,
    );
  });

  test(
    'resolveNavigationTabIndex lets detail and reader routes inherit source tabs',
    () {
      expect(
        resolveNavigationTabIndex(
          Uri.parse('https://www.2026copy.com/comic/demo'),
          sourceTabIndex: 3,
        ),
        3,
      );
      expect(
        resolveNavigationTabIndex(
          Uri.parse('https://www.2026copy.com/comic/demo/chapter/1'),
          sourceTabIndex: 2,
        ),
        2,
      );
      expect(
        resolveNavigationTabIndex(
          Uri.parse('https://www.2026copy.com/comic/demo'),
          sourceTabIndex: 2,
        ),
        2,
      );
      expect(
        resolveNavigationTabIndex(
          Uri.parse('https://www.2026copy.com/comics'),
          sourceTabIndex: 3,
        ),
        1,
      );
      expect(
        resolveNavigationTabIndex(
          Uri.parse('https://www.2026copy.com/rank'),
          sourceTabIndex: 1,
        ),
        2,
      );
      expect(
        resolveNavigationTabIndex(
          Uri.parse('https://www.2026copy.com/comic/demo'),
        ),
        1,
      );
    },
  );

  test('buildSearchUri keeps page and q_type in search routes', () {
    expect(
      AppConfig.buildSearchUri('海贼王').toString(),
      'https://www.2026copy.com/search?q=%E6%B5%B7%E8%B4%BC%E7%8E%8B',
    );
    expect(
      AppConfig.buildSearchUri('海贼王', page: 3, qType: 'author').toString(),
      'https://www.2026copy.com/search?q=%E6%B5%B7%E8%B4%BC%E7%8E%8B&page=3&q_type=author',
    );
  });

  test('buildPagedUri updates and clears the page query parameter', () {
    final Uri searchPage = AppConfig.buildPagedUri(
      Uri.parse('https://www.2026copy.com/search?q=robot&q_type=author'),
      page: 5,
    );
    expect(searchPage.queryParameters['q'], 'robot');
    expect(searchPage.queryParameters['q_type'], 'author');
    expect(searchPage.queryParameters['page'], '5');

    final Uri firstPage = AppConfig.buildPagedUri(searchPage, page: 1);
    expect(firstPage.queryParameters['q'], 'robot');
    expect(firstPage.queryParameters['q_type'], 'author');
    expect(firstPage.queryParameters.containsKey('page'), isFalse);
  });
}
