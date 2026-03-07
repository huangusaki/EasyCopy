import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/page_transition_scope.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'discover and rank query changes stay within the same transition scope',
    () {
      final DiscoverPageData discoverPage = DiscoverPageData(
        title: '发现',
        uri: 'https://example.com/comics?theme=maoxian',
        filters: const <FilterGroupData>[],
        items: const <ComicCardData>[],
        pager: const PagerData(),
        spotlight: const <ComicCardData>[],
      );
      final RankPageData rankPage = RankPageData(
        title: '排行',
        uri: 'https://example.com/rank?type=male&table=day',
        categories: const <LinkAction>[],
        periods: const <LinkAction>[],
        items: const <RankEntryData>[],
      );

      expect(
        standardPageTransitionScope(
          discoverPage,
          Uri.parse('https://example.com/comics?ordering=-datetime_updated'),
        ),
        'discover',
      );
      expect(
        standardPageTransitionScope(
          rankPage,
          Uri.parse('https://example.com/rank?type=female&table=week'),
        ),
        'rank',
      );
    },
  );

  test('search and detail routes keep distinct transition scopes', () {
    final String firstSearchScope = standardPageTransitionScope(
      null,
      Uri.parse('https://example.com/search?q=robot'),
    );
    final String secondSearchScope = standardPageTransitionScope(
      null,
      Uri.parse('https://example.com/search?q=magic'),
    );
    final String firstDetailScope = standardPageTransitionScope(
      null,
      Uri.parse('https://example.com/comic/demo-a'),
    );
    final String secondDetailScope = standardPageTransitionScope(
      null,
      Uri.parse('https://example.com/comic/demo-b'),
    );

    expect(firstSearchScope, isNot(secondSearchScope));
    expect(firstDetailScope, isNot(secondDetailScope));
  });
}
