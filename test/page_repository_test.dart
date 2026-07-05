import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/services/navigation_request_guard.dart';
import 'package:reader/services/page_cache_store.dart';
import 'package:reader/services/page_repository.dart';

void main() {
  test(
    'author comics route uses HTML loader instead of standard WebView loader',
    () async {
      final Directory cacheDirectory = await Directory.systemTemp.createTemp(
        'easycopy_page_repository_test_',
      );
      addTearDown(() async {
        if (await cacheDirectory.exists()) {
          await cacheDirectory.delete(recursive: true);
        }
      });

      var htmlLoaderCalls = 0;
      var standardLoaderCalls = 0;
      final Uri authorUri = Uri.parse(
        'https://www.mangacopy.com/author/xiaoyezhongzhangda/comics',
      );
      final PageRepository repository = PageRepository(
        cacheStore: PageCacheStore(
          directoryProvider: () async => cacheDirectory,
        ),
        standardPageLoader:
            (
              Uri uri, {
              required String authScope,
              NavigationRequestContext? requestContext,
            }) async {
              standardLoaderCalls += 1;
              throw StateError('author route should not use standard loader');
            },
        htmlPageLoader: (Uri uri, {required String authScope}) async {
          htmlLoaderCalls += 1;
          return DiscoverPageData(
            title: '作者作品',
            uri: uri.toString(),
            filters: const <FilterGroupData>[],
            items: const <ComicCardData>[],
            pager: const PagerData(),
            spotlight: const <ComicCardData>[],
          );
        },
      );

      final SitePage page = await repository.loadFresh(
        authorUri,
        authScope: 'guest',
      );

      expect(Uri.parse(page.uri).path, authorUri.path);
      expect(htmlLoaderCalls, 1);
      expect(standardLoaderCalls, 0);
    },
  );
}
