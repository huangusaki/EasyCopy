import 'package:reader/config/app_config.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/services/comic_download_service.dart';
import 'package:reader/services/comic_download_service/download_contracts.dart';
import 'package:reader/services/download_queue_manager/task_executor.dart';
import 'package:reader/services/download_queue_store.dart';
import 'package:reader/services/reader_page_download_resolver.dart';
import 'package:reader/services/site_session.dart';

class ReaderDownloadTaskRunner implements DownloadTaskRunner {
  const ReaderDownloadTaskRunner({
    required SiteSession session,
    required ComicDownloadService downloadService,
    required ReaderPageDownloadResolver pageResolver,
  }) : _session = session,
       _downloadService = downloadService,
       _pageResolver = pageResolver;

  final SiteSession _session;
  final ComicDownloadService _downloadService;
  final ReaderPageDownloadResolver _pageResolver;

  @override
  Future<ReaderPageData> prepare(DownloadQueueTask task) async {
    await _session.ensureInitialized();
    return _pageResolver.resolve(
      AppConfig.rewriteToCurrentHost(Uri.parse(task.chapterHref)),
    );
  }

  @override
  Future<void> download(
    DownloadQueueTask task,
    ReaderPageData page, {
    required ChapterDownloadPauseChecker shouldPause,
    required ChapterDownloadCancelChecker shouldCancel,
    ChapterDownloadProgressCallback? onProgress,
  }) {
    return _downloadService.downloadChapter(
      page,
      cookieHeader: _session.cookieHeader,
      comicUri: task.comicUri,
      chapterHref: task.chapterHref,
      chapterLabel: task.chapterLabel,
      coverUrl: task.coverUrl,
      detailSnapshot: task.detailSnapshot,
      shouldPause: shouldPause,
      shouldCancel: shouldCancel,
      onProgress: onProgress,
    );
  }
}
