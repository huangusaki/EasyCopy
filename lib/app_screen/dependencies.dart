import 'package:reader/services/comic_download_service.dart';
import 'package:reader/services/download_queue_store.dart';
import 'package:reader/services/download_storage_service.dart';
import 'package:reader/services/host_manager.dart';
import 'package:reader/services/local_library_store.dart';
import 'package:reader/services/local_profile_page_loader.dart';
import 'package:reader/services/page_cache_store.dart';
import 'package:reader/services/reader_progress_store.dart';
import 'package:reader/services/search_history_store.dart';
import 'package:reader/services/site_api_client.dart';
import 'package:reader/services/site_session.dart';

class AppScreenServices {
  AppScreenServices({
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
  }) : hostManager = hostManager ?? HostManager.instance,
       session = session ?? SiteSession.instance,
       siteApiClient = siteApiClient ?? SiteApiClient.instance,
       readerProgressStore =
           readerProgressStore ?? ReaderProgressStore.instance,
       localLibraryStore = localLibraryStore ?? LocalLibraryStore.instance,
       localProfilePageLoader =
           localProfilePageLoader ?? LocalProfilePageLoader.instance,
       searchHistoryStore = searchHistoryStore ?? SearchHistoryStore.instance,
       downloadService = downloadService ?? ComicDownloadService.instance,
       downloadStorageService =
           downloadStorageService ?? DownloadStorageService.instance,
       downloadQueueStore = downloadQueueStore ?? DownloadQueueStore.instance,
       pageCacheStore = pageCacheStore ?? PageCacheStore.instance;

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
}
