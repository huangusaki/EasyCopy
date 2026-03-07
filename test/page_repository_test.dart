import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_copy/config/app_config.dart';
import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/services/page_cache_store.dart';
import 'package:easy_copy/services/page_probe_service.dart';
import 'package:easy_copy/services/page_repository.dart';
import 'package:easy_copy/services/site_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'easy_copy_page_repository',
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  PageCacheStore buildCacheStore(DateTime now) {
    return PageCacheStore(
      directoryProvider: () async => tempDir,
      now: () => now,
    );
  }

  test('readCached prefers memory after the first disk-backed read', () async {
    final DateTime now = DateTime(2026, 3, 7, 12);
    int loaderCount = 0;
    final PageRepository repository = PageRepository(
      cacheStore: buildCacheStore(now),
      probeService: _buildProbeService('<html></html>'),
      apiClient: FakeSiteApiClient(_buildLoggedOutProfile),
      standardPageLoader: (Uri uri, {required String authScope}) async {
        loaderCount += 1;
        return HomePageData(
          title: '首页',
          uri: uri.toString(),
          heroBanners: const <HeroBannerData>[],
          sections: const <ComicSectionData>[],
        );
      },
    );

    final Uri uri = Uri.parse('https://example.com/');
    final PageQueryKey key = PageQueryKey.forUri(uri, authScope: 'guest');

    await repository.loadFresh(uri, authScope: 'guest');
    repository.clearMemory();

    final CachedPageHit? firstHit = await repository.readCached(key);
    final CachedPageHit? secondHit = await repository.readCached(key);

    expect(loaderCount, 1);
    expect(firstHit, isNotNull);
    expect(secondHit, isNotNull);
    expect(firstHit!.page.title, '首页');
    expect(secondHit!.page.title, '首页');
    expect(loaderCount, 1);
  });

  test(
    'concurrent loadFresh requests share the same underlying load',
    () async {
      final Completer<EasyCopyPage> completer = Completer<EasyCopyPage>();
      int loaderCount = 0;
      final PageRepository repository = PageRepository(
        cacheStore: buildCacheStore(DateTime(2026, 3, 7, 12)),
        probeService: _buildProbeService('<html></html>'),
        apiClient: FakeSiteApiClient(_buildLoggedOutProfile),
        standardPageLoader: (Uri uri, {required String authScope}) async {
          loaderCount += 1;
          return completer.future;
        },
      );

      final Uri uri = Uri.parse('https://example.com/comics');
      final Future<EasyCopyPage> futureA = repository.loadFresh(
        uri,
        authScope: 'guest',
      );
      final Future<EasyCopyPage> futureB = repository.loadFresh(
        uri,
        authScope: 'guest',
      );

      await Future<void>.delayed(Duration.zero);
      expect(loaderCount, 1);

      completer.complete(
        HomePageData(
          title: '发现',
          uri: uri.toString(),
          heroBanners: const <HeroBannerData>[],
          sections: const <ComicSectionData>[],
        ),
      );

      final List<EasyCopyPage> results = await Future.wait<EasyCopyPage>(
        <Future<EasyCopyPage>>[futureA, futureB],
      );
      expect(results[0].uri, uri.toString());
      expect(results[1].uri, uri.toString());
    },
  );

  test(
    'concurrent revalidate requests share a single probe and refresh load',
    () async {
      int loaderCount = 0;
      int probeCount = 0;
      final PageRepository repository = PageRepository(
        cacheStore: buildCacheStore(DateTime(2026, 3, 7, 12)),
        probeService: _buildProbeService(
          '<html><body><div class="content-box"><div class="swiperList"></div></div><div class="comicRank"></div><a href="/comic/new"></a></body></html>',
          onProbe: () {
            probeCount += 1;
          },
        ),
        apiClient: FakeSiteApiClient(_buildLoggedOutProfile),
        standardPageLoader: (Uri uri, {required String authScope}) async {
          loaderCount += 1;
          return HomePageData(
            title: loaderCount == 1 ? '旧首页' : '新首页',
            uri: uri.toString(),
            heroBanners: const <HeroBannerData>[],
            sections: const <ComicSectionData>[],
          );
        },
      );

      final Uri uri = Uri.parse('https://example.com/');
      final PageQueryKey key = PageQueryKey.forUri(uri, authScope: 'guest');
      await repository.loadFresh(uri, authScope: 'guest');
      final CachedPageHit? cachedHit = await repository.readCached(key);

      await Future.wait<void>(<Future<void>>[
        repository.revalidate(uri, key: key, envelope: cachedHit!.envelope),
        repository.revalidate(uri, key: key, envelope: cachedHit.envelope),
      ]);

      expect(probeCount, 1);
      expect(loaderCount, 2);
    },
  );

  test('authScope remains isolated for the same route', () async {
    int loaderCount = 0;
    final PageRepository repository = PageRepository(
      cacheStore: buildCacheStore(DateTime(2026, 3, 7, 12)),
      probeService: _buildProbeService('<html></html>'),
      apiClient: FakeSiteApiClient(_buildLoggedOutProfile),
      standardPageLoader: (Uri uri, {required String authScope}) async {
        loaderCount += 1;
        return HomePageData(
          title: authScope,
          uri: uri.toString(),
          heroBanners: const <HeroBannerData>[],
          sections: const <ComicSectionData>[],
        );
      },
    );

    final Uri uri = Uri.parse('https://example.com/comics');
    await repository.loadFresh(uri, authScope: 'guest');
    await repository.loadFresh(uri, authScope: 'user:42');

    final CachedPageHit? guestHit = await repository.readCached(
      PageQueryKey.forUri(uri, authScope: 'guest'),
    );
    final CachedPageHit? userHit = await repository.readCached(
      PageQueryKey.forUri(uri, authScope: 'user:42'),
    );

    expect(loaderCount, 2);
    expect(guestHit!.page.title, 'guest');
    expect(userHit!.page.title, 'user:42');
  });

  test(
    'profile and normal pages share the same repository semantics',
    () async {
      final PageRepository repository = PageRepository(
        cacheStore: buildCacheStore(DateTime(2026, 3, 7, 12)),
        probeService: _buildProbeService('<html></html>'),
        apiClient: FakeSiteApiClient(
          () async => ProfilePageData(
            title: '我的',
            uri: AppConfig.profileUri.toString(),
            isLoggedIn: true,
            user: const ProfileUserData(userId: '42', username: 'demo'),
            collections: const <ProfileLibraryItem>[],
            history: const <ProfileHistoryItem>[],
          ),
        ),
        standardPageLoader: (Uri uri, {required String authScope}) async {
          return HomePageData(
            title: '首页',
            uri: uri.toString(),
            heroBanners: const <HeroBannerData>[],
            sections: const <ComicSectionData>[],
          );
        },
      );

      await repository.loadFresh(AppConfig.profileUri, authScope: 'user:42');
      await repository.loadFresh(
        Uri.parse('https://example.com/'),
        authScope: 'guest',
      );

      expect(
        await repository.readCached(
          PageQueryKey.forUri(AppConfig.profileUri, authScope: 'user:42'),
        ),
        isNotNull,
      );
      expect(
        await repository.readCached(
          PageQueryKey.forUri(
            Uri.parse('https://example.com/'),
            authScope: 'guest',
          ),
        ),
        isNotNull,
      );
    },
  );

  test('loadFresh stores redirected pages under the final route key', () async {
    final PageRepository repository = PageRepository(
      cacheStore: buildCacheStore(DateTime(2026, 3, 7, 12)),
      probeService: _buildProbeService('<html></html>'),
      apiClient: FakeSiteApiClient(_buildLoggedOutProfile),
      standardPageLoader: (Uri uri, {required String authScope}) async {
        return HomePageData(
          title: '重定向首页',
          uri: 'https://example.com/comics?page=2',
          heroBanners: const <HeroBannerData>[],
          sections: const <ComicSectionData>[],
        );
      },
    );

    final Uri requestedUri = Uri.parse('https://example.com/search?q=jump');
    await repository.loadFresh(requestedUri, authScope: 'guest');

    expect(
      await repository.readCached(
        PageQueryKey.forUri(requestedUri, authScope: 'guest'),
      ),
      isNull,
    );
    expect(
      await repository.readCached(
        PageQueryKey.forUri(
          Uri.parse('https://example.com/comics?page=2'),
          authScope: 'guest',
        ),
      ),
      isNotNull,
    );
  });
}

PageProbeService _buildProbeService(String html, {void Function()? onProbe}) {
  return PageProbeService(
    client: MockClient((http.Request request) async {
      onProbe?.call();
      return http.Response.bytes(utf8.encode(html), 200);
    }),
    now: () => DateTime(2026, 3, 7, 12),
    userAgent: 'test-agent',
  );
}

Future<ProfilePageData> _buildLoggedOutProfile() async {
  return ProfilePageData.loggedOut(uri: AppConfig.profileUri.toString());
}

class FakeSiteApiClient extends SiteApiClient {
  FakeSiteApiClient(this._loader)
    : super(
        client: MockClient(
          (http.Request request) async =>
              http.Response.bytes(utf8.encode('{}'), 200),
        ),
      );

  final Future<ProfilePageData> Function() _loader;

  @override
  Future<ProfilePageData> loadProfile() {
    return _loader();
  }
}
