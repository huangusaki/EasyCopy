import 'package:easy_copy/config/app_config.dart';
import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/services/local_library_store.dart';
import 'package:easy_copy/services/site_api_client.dart';
import 'package:easy_copy/services/site_session.dart';

class LocalProfilePageLoader {
  LocalProfilePageLoader({
    LocalLibraryStore? libraryStore,
    SiteApiClient? apiClient,
    SiteSession? session,
  }) : _libraryStore = libraryStore ?? LocalLibraryStore.instance,
       _apiClient = apiClient ?? SiteApiClient.instance,
       _session = session ?? SiteSession.instance;

  static final LocalProfilePageLoader instance = LocalProfilePageLoader();

  final LocalLibraryStore _libraryStore;
  final SiteApiClient _apiClient;
  final SiteSession _session;

  Future<ProfilePageData> loadProfile(
    Uri uri, {
    required String authScope,
  }) async {
    await _libraryStore.ensureInitialized();
    await _session.ensureInitialized();

    final ProfileSubview view = AppConfig.profileSubviewForUri(uri);
    final int activePage = AppConfig.profilePageForUri(uri);

    final bool isLoggedIn = authScope != LocalLibraryStore.guestScope;
    final String guestScope = LocalLibraryStore.guestScope;
    final String continueScope = LocalLibraryStore.continueReadingScope;

    ProfileHistoryItem? continueReading;
    if (view == ProfileSubview.root) {
      final ProfileHistoryItem? globalContinue = await _libraryStore
          .latestContinueReading(continueScope);
      continueReading = globalContinue;
      if (globalContinue == null) {
        // Migration fallback: older builds stored continue-reading progress
        // inside guest/auth scopes. Keep displaying it and best-effort copy
        // into the global continue-reading scope.
        continueReading ??=
            isLoggedIn
                ? await _libraryStore.latestContinueReading(authScope)
                : null;
        continueReading ??= await _libraryStore.latestContinueReading(guestScope);
        if (continueReading != null) {
          try {
            await _libraryStore.importHistory(
              continueScope,
              <ProfileHistoryItem>[continueReading!],
              maxEntries: 1,
            );
          } catch (_) {
            // Best-effort migration only.
          }
        }
      }
    }

    if (isLoggedIn) {
      final ProfilePageData serverPage = await _apiClient.loadProfile(uri: uri);
      // Continue reading is always local and should not use server history.
      return serverPage.copyWith(
        continueReading: continueReading,
        clearContinueReading: continueReading == null,
      );
    }

    final (List<ProfileLibraryItem> collectionsPreview, int collectionsTotal) =
        await _libraryStore.readCollectionsPage(
          guestScope,
          page: view == ProfileSubview.collections ? activePage : 1,
          pageSize: 20,
        );
    final (List<ProfileHistoryItem> historyPreview, int historyTotal) =
        await _libraryStore.readHistoryPage(
          guestScope,
          page: view == ProfileSubview.history ? activePage : 1,
          pageSize: 20,
        );

    switch (view) {
      case ProfileSubview.collections:
        return ProfilePageData(
          title: '我的收藏',
          uri: uri.toString(),
          isLoggedIn: isLoggedIn,
          user: null,
          collections: collectionsPreview,
          collectionsPager: _buildPager(
            view: ProfileSubview.collections,
            currentPage: activePage,
            totalItems: collectionsTotal,
            pageSize: 20,
          ),
          collectionsTotal: collectionsTotal,
          history: const <ProfileHistoryItem>[],
          historyPager: const PagerData(),
          historyTotal: 0,
        );
      case ProfileSubview.history:
        return ProfilePageData(
          title: '浏览历史',
          uri: uri.toString(),
          isLoggedIn: isLoggedIn,
          user: null,
          collections: const <ProfileLibraryItem>[],
          collectionsPager: const PagerData(),
          collectionsTotal: 0,
          history: historyPreview,
          historyPager: _buildPager(
            view: ProfileSubview.history,
            currentPage: activePage,
            totalItems: historyTotal,
            pageSize: 20,
          ),
          historyTotal: historyTotal,
        );
      case ProfileSubview.cached:
      case ProfileSubview.root:
        return ProfilePageData(
          title: '我的',
          uri: uri.toString(),
          isLoggedIn: isLoggedIn,
          user: null,
          continueReading: continueReading,
          collections: collectionsPreview,
          history: historyPreview,
          collectionsTotal: collectionsTotal,
          historyTotal: historyTotal,
        );
    }
  }

  PagerData _buildPager({
    required ProfileSubview view,
    required int currentPage,
    required int totalItems,
    required int pageSize,
  }) {
    final int normalizedPage = currentPage < 1 ? 1 : currentPage;
    final int normalizedTotalItems = totalItems < 0 ? 0 : totalItems;
    final int normalizedPageSize = pageSize.clamp(1, 100);
    final int totalPages = (normalizedTotalItems / normalizedPageSize)
        .ceil()
        .clamp(1, 999999);
    final String unit = switch (view) {
      ProfileSubview.collections => '部',
      ProfileSubview.history => '条',
      _ => '条',
    };
    return PagerData(
      currentLabel: '$normalizedPage',
      totalLabel: '共$totalPages页 · $normalizedTotalItems$unit',
      prevHref: normalizedPage > 1
          ? AppConfig.buildProfileUri(view: view, page: normalizedPage - 1)
                .toString()
          : '',
      nextHref: normalizedPage < totalPages
          ? AppConfig.buildProfileUri(view: view, page: normalizedPage + 1)
                .toString()
          : '',
    );
  }

}
