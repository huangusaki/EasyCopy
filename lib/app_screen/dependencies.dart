import 'package:reader/models/page_models.dart';
import 'package:reader/reader/dependencies.dart';
import 'package:reader/services/app_preferences_controller.dart';
import 'package:reader/services/comic_download_service.dart';
import 'package:reader/services/desktop_page_extractor.dart';
import 'package:reader/services/download_queue_store.dart';
import 'package:reader/services/download_storage_service.dart';
import 'package:reader/services/host_manager.dart';
import 'package:reader/services/local_library_store.dart';
import 'package:reader/services/local_profile_page_loader.dart';
import 'package:reader/services/page_cache_store.dart';
import 'package:reader/services/page_repository.dart';
import 'package:reader/services/reader_download_task_runner.dart';
import 'package:reader/services/reader_page_download_resolver.dart';
import 'package:reader/services/reader_platform_bridge.dart';
import 'package:reader/services/reader_progress_store.dart';
import 'package:reader/services/search_history_store.dart';
import 'package:reader/services/site_api_client.dart';
import 'package:reader/services/site_html_page_loader.dart';
import 'package:reader/services/site_page_source.dart';
import 'package:reader/services/site_session.dart';
import 'package:reader/utils/platform_capabilities.dart';

class AppScreenServices {
  factory AppScreenServices({
    HostManager? hostManager,
    SiteSession? session,
    SiteApiClient? siteApiClient,
    ReaderProgressStore? readerProgressStore,
    LocalLibraryStore? localLibraryStore,
    LocalProfilePageLoader? localProfilePageLoader,
    SearchHistoryStore? searchHistoryStore,
    ComicDownloadService? downloadService,
    DownloadStorageService? downloadStorageService,
    DownloadQueueStore? downloadQueueStore,
    PageCacheStore? pageCacheStore,
    SiteHtmlPageLoader? siteHtmlPageLoader,
    DesktopPageExtractor? desktopPageExtractor,
    DesktopPageLoader? desktopPageLoader,
    SitePageSource? htmlPageSource,
  }) {
    final HostManager resolvedHostManager = hostManager ?? HostManager.instance;
    final SiteSession resolvedSession = session ?? SiteSession.instance;
    final SiteApiClient resolvedApiClient =
        siteApiClient ??
        (session == null
            ? SiteApiClient.instance
            : SiteApiClient(session: resolvedSession));
    final LocalLibraryStore resolvedLibraryStore =
        localLibraryStore ?? LocalLibraryStore.instance;
    final DownloadStorageService resolvedStorageService =
        downloadStorageService ?? DownloadStorageService.instance;
    final DesktopPageExtractor resolvedDesktopExtractor =
        desktopPageExtractor ??
        (session == null
            ? DesktopPageExtractor.instance
            : DesktopPageExtractor(session: resolvedSession));
    final DesktopPageLoader resolvedDesktopLoader =
        desktopPageLoader ?? resolvedDesktopExtractor.loadPage;
    return AppScreenServices._(
      hostManager: resolvedHostManager,
      session: resolvedSession,
      siteApiClient: resolvedApiClient,
      readerProgressStore: readerProgressStore ?? ReaderProgressStore.instance,
      localLibraryStore: resolvedLibraryStore,
      localProfilePageLoader:
          localProfilePageLoader ??
          LocalProfilePageLoader(
            libraryStore: resolvedLibraryStore,
            apiClient: resolvedApiClient,
            session: resolvedSession,
          ),
      searchHistoryStore: searchHistoryStore ?? SearchHistoryStore.instance,
      downloadService:
          downloadService ??
          (downloadStorageService == null
              ? ComicDownloadService.instance
              : ComicDownloadService(storageService: resolvedStorageService)),
      downloadStorageService: resolvedStorageService,
      downloadQueueStore: downloadQueueStore ?? DownloadQueueStore.instance,
      pageCacheStore: pageCacheStore ?? PageCacheStore.instance,
      desktopPageLoader: resolvedDesktopLoader,
      desktopPageExtractor: resolvedDesktopExtractor,
      htmlPageSource:
          htmlPageSource ??
          PlatformHtmlPageSource(
            htmlLoader:
                siteHtmlPageLoader ??
                (session == null && hostManager == null
                    ? SiteHtmlPageLoader.instance
                    : SiteHtmlPageLoader(
                        session: resolvedSession,
                        hostManager: resolvedHostManager,
                      )),
            desktopLoader: resolvedDesktopLoader,
            useDesktopWebView: PlatformCapabilities.supportsDesktopWebView,
          ),
    );
  }

  const AppScreenServices._({
    required this.hostManager,
    required this.session,
    required this.siteApiClient,
    required this.readerProgressStore,
    required this.localLibraryStore,
    required this.localProfilePageLoader,
    required this.searchHistoryStore,
    required this.downloadService,
    required this.downloadStorageService,
    required this.downloadQueueStore,
    required this.pageCacheStore,
    required this.desktopPageLoader,
    required this.desktopPageExtractor,
    required this.htmlPageSource,
  });

  final HostManager hostManager;
  final SiteSession session;
  final SiteApiClient siteApiClient;
  final ReaderProgressStore readerProgressStore;
  final LocalLibraryStore localLibraryStore;
  final LocalProfilePageLoader localProfilePageLoader;
  final SearchHistoryStore searchHistoryStore;
  final ComicDownloadService downloadService;
  final DownloadStorageService downloadStorageService;
  final DownloadQueueStore downloadQueueStore;
  final PageCacheStore pageCacheStore;
  final DesktopPageLoader desktopPageLoader;
  final DesktopPageExtractor desktopPageExtractor;
  final SitePageSource htmlPageSource;

  ReaderScreenServices createReaderServices(
    AppPreferencesController preferencesController,
  ) {
    return ReaderScreenServices(
      preferencesController: preferencesController,
      progressStore: readerProgressStore,
      platformBridge: ReaderPlatformBridge.instance,
      apiClient: siteApiClient,
      session: session,
      localLibraryStore: localLibraryStore,
    );
  }

  PageRepository createPageRepository({
    required SitePageLoader standardLoader,
  }) {
    return PageRepository(
      cacheStore: pageCacheStore,
      source: RoutedSitePageSource(
        apiClient: siteApiClient,
        profileLoader: localProfilePageLoader.loadProfile,
        standardLoader: standardLoader,
        htmlSource: htmlPageSource,
      ),
    );
  }

  ReaderDownloadTaskRunner createDownloadTaskRunner({
    required PageRepository pageRepository,
    required ReaderPageLoader webViewFallback,
  }) {
    return ReaderDownloadTaskRunner(
      session: session,
      downloadService: downloadService,
      pageResolver: ReaderPageDownloadResolver(
        loadFromStorageCache: (Uri uri) =>
            downloadService.loadCachedReaderPage(uri.toString()),
        loadFromPageCache: (Uri uri) async {
          final CachedPageHit? hit = await pageRepository.readCached(
            PageQueryKey.forUri(uri, authScope: 'guest'),
          );
          return hit?.page is ReaderPageData
              ? hit!.page as ReaderPageData
              : null;
        },
        loadFromLightweightSource: (Uri uri) async {
          final SitePage page = await htmlPageSource.load(
            uri,
            authScope: 'guest',
          );
          if (page is! ReaderPageData) {
            throw StateError('章节解析失败');
          }
          return page;
        },
        loadFromWebViewFallback: webViewFallback,
      ),
    );
  }
}
