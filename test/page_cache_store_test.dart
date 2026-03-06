import 'dart:io';

import 'package:easy_copy/config/app_config.dart';
import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/services/page_cache_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('page cache keeps entries readable across soft ttl and refreshes validation', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'easy_copy_cache',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    DateTime now = DateTime(2026, 3, 6, 12);
    final PageCacheStore store = PageCacheStore(
      directoryProvider: () async => tempDir,
      now: () => now,
    );

    final HomePageData page = HomePageData(
      title: '首頁',
      uri: 'https://www.2026copy.com/',
      heroBanners: const <HeroBannerData>[],
      sections: const <ComicSectionData>[],
    );
    await store.writeEnvelope(
      PageCacheStore.buildEnvelope(
        routeKey: '/',
        page: page,
        fingerprint: 'home-fingerprint',
        authScope: 'guest',
        now: now,
      ),
    );

    now = now.add(const Duration(minutes: 4));
    final CachedPageEnvelope? staleEntry = await store.read(
      '/',
      authScope: 'guest',
    );
    expect(staleEntry, isNotNull);
    expect(staleEntry!.isSoftExpired(now), isTrue);
    expect(staleEntry.isHardExpired(now), isFalse);

    await store.refreshValidation('/', authScope: 'guest');
    final CachedPageEnvelope? refreshedEntry = await store.read(
      '/',
      authScope: 'guest',
    );
    expect(refreshedEntry, isNotNull);
    expect(refreshedEntry!.isSoftExpired(now), isFalse);
  });

  test('page cache isolates authenticated entries from guest entries', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'easy_copy_cache_auth',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final PageCacheStore store = PageCacheStore(
      directoryProvider: () async => tempDir,
      now: () => DateTime(2026, 3, 6, 12),
    );

    final ProfilePageData profilePage = ProfilePageData(
      title: '我的',
      uri: 'https://www.2026copy.com/person/home',
      isLoggedIn: true,
      user: const ProfileUserData(
        userId: '42',
        username: 'demo',
      ),
      collections: const <ProfileLibraryItem>[],
      history: const <ProfileHistoryItem>[],
    );
    final HomePageData guestPage = HomePageData(
      title: '首頁',
      uri: 'https://www.2026copy.com/',
      heroBanners: const <HeroBannerData>[],
      sections: const <ComicSectionData>[],
    );

    await store.writeEnvelope(
      PageCacheStore.buildEnvelope(
        routeKey: AppConfig.profileRouteKey,
        page: profilePage,
        fingerprint: 'profile',
        authScope: 'user:42',
        now: DateTime(2026, 3, 6, 12),
      ),
    );
    await store.writeEnvelope(
      PageCacheStore.buildEnvelope(
        routeKey: '/',
        page: guestPage,
        fingerprint: 'guest',
        authScope: 'guest',
        now: DateTime(2026, 3, 6, 12),
      ),
    );

    expect(
      await store.read(AppConfig.profileRouteKey, authScope: 'guest'),
      isNull,
    );
    expect(await store.read('/', authScope: 'guest'), isNotNull);
    expect(
      await store.read(AppConfig.profileRouteKey, authScope: 'user:42'),
      isNotNull,
    );

    await store.removeAuthenticatedEntries();

    expect(
      await store.read(AppConfig.profileRouteKey, authScope: 'user:42'),
      isNull,
    );
    expect(await store.read('/', authScope: 'guest'), isNotNull);
  });
}
