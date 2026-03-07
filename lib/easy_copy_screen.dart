import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:crypto/crypto.dart';
import 'package:easy_copy/config/app_config.dart';
import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/services/comic_download_service.dart';
import 'package:easy_copy/services/download_queue_store.dart';
import 'package:easy_copy/services/host_manager.dart';
import 'package:easy_copy/services/image_cache.dart';
import 'package:easy_copy/services/page_cache_store.dart';
import 'package:easy_copy/services/page_repository.dart';
import 'package:easy_copy/services/primary_tab_session_store.dart';
import 'package:easy_copy/services/reader_progress_store.dart';
import 'package:easy_copy/services/site_session.dart';
import 'package:easy_copy/webview/page_extractor_script.dart';
import 'package:easy_copy/widgets/auth_webview_screen.dart';
import 'package:easy_copy/widgets/native_login_screen.dart';
import 'package:easy_copy/widgets/profile_page_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

class EasyCopyScreen extends StatefulWidget {
  const EasyCopyScreen({super.key});

  @override
  State<EasyCopyScreen> createState() => _EasyCopyScreenState();
}

class _EasyCopyScreenState extends State<EasyCopyScreen> {
  late final WebViewController _controller;
  late final WebViewController _downloadController;
  final WebViewCookieManager _cookieManager = WebViewCookieManager();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _standardScrollController = ScrollController();
  final ScrollController _readerScrollController = ScrollController();
  final HostManager _hostManager = HostManager.instance;
  final SiteSession _session = SiteSession.instance;
  final ReaderProgressStore _readerProgressStore = ReaderProgressStore.instance;
  final ComicDownloadService _downloadService = ComicDownloadService.instance;
  final DownloadQueueStore _downloadQueueStore = DownloadQueueStore.instance;
  final PrimaryTabSessionStore _tabSessionStore = PrimaryTabSessionStore(
    rootUris: <int, Uri>{
      for (int index = 0; index < appDestinations.length; index += 1)
        index: appDestinations[index].uri,
    },
  );
  final ValueNotifier<DownloadQueueSnapshot> _downloadQueueSnapshotNotifier =
      ValueNotifier<DownloadQueueSnapshot>(const DownloadQueueSnapshot());
  late final PageRepository _pageRepository;

  int _selectedIndex = 0;
  int _activeLoadId = 0;
  bool _isFailingOver = false;
  int _consecutiveFrameFailures = 0;
  bool _isDiscoverThemeExpanded = false;
  List<CachedComicLibraryEntry> _cachedComics =
      const <CachedComicLibraryEntry>[];
  bool _isLoadingCachedComics = true;
  int _downloadActiveLoadId = 0;
  Completer<ReaderPageData>? _downloadExtractionCompleter;
  Timer? _readerProgressDebounce;
  double? _lastPersistedReaderOffset;
  bool _isProcessingDownloadQueue = false;
  bool _suspendStandardScrollTracking = false;
  final Set<String> _cancelledComicKeys = <String>{};
  final Map<String, String> _cancelledComicTitles = <String, String>{};
  _PendingPageLoad? _pendingPageLoad;
  NavigationIntent? _nextFreshNavigationIntent;

  @override
  void initState() {
    super.initState();
    _controller = _buildController();
    _downloadController = _buildDownloadController();
    _pageRepository = PageRepository(
      standardPageLoader: _loadStandardPageFresh,
    );
    _standardScrollController.addListener(_handleStandardScroll);
    _readerScrollController.addListener(_handleReaderScroll);
    unawaited(_bootstrap());
    _syncSearchController();
  }

  @override
  void dispose() {
    _persistCurrentReaderProgress();
    _readerProgressDebounce?.cancel();
    _standardScrollController.removeListener(_handleStandardScroll);
    _readerScrollController.removeListener(_handleReaderScroll);
    _searchController.dispose();
    _standardScrollController.dispose();
    _readerScrollController.dispose();
    _downloadQueueSnapshotNotifier.dispose();
    super.dispose();
  }

  PrimaryTabRouteEntry get _currentEntry =>
      _tabSessionStore.currentEntry(_selectedIndex);

  Uri get _currentUri => _currentEntry.uri;

  EasyCopyPage? get _page => _currentEntry.page;

  bool get _isLoading => _currentEntry.isLoading;

  String? get _errorMessage => _currentEntry.errorMessage;

  String _authScopeForUri(Uri uri) {
    if (_isProfileUri(uri)) {
      return _session.authScope;
    }
    return 'guest';
  }

  PageQueryKey _pageQueryKeyForUri(Uri uri, {String? authScope}) {
    return PageQueryKey.forUri(
      uri,
      authScope: authScope ?? _authScopeForUri(uri),
    );
  }

  void _mutateSessionState(VoidCallback mutation, {bool syncSearch = true}) {
    if (!mounted) {
      mutation();
      if (syncSearch) {
        _syncSearchController();
      }
      return;
    }
    setState(mutation);
    if (syncSearch) {
      _syncSearchController();
    }
  }

  Future<void> _bootstrap() async {
    await Future.wait(<Future<void>>[
      _hostManager.ensureInitialized(),
      _session.ensureInitialized(),
      _downloadQueueStore.ensureInitialized(),
      _readerProgressStore.ensureInitialized(),
    ]);
    await _refreshCachedComics();
    await _restoreDownloadQueue();
    final Uri homeUri = appDestinations.first.uri;
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedIndex = tabIndexForUri(homeUri);
    });
    _syncSearchController();
    await _loadUri(homeUri, historyMode: NavigationIntent.resetToRoot);
    unawaited(_ensureDownloadQueueRunning());
  }

  WebViewController _buildController() {
    return WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(AppConfig.desktopUserAgent)
      ..addJavaScriptChannel(
        'easyCopyBridge',
        onMessageReceived: _handleBridgeMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            final Uri? nextUri = Uri.tryParse(request.url);
            if (_isLoginUri(nextUri)) {
              unawaited(_openAuthFlow());
              return NavigationDecision.prevent;
            }
            if (!AppConfig.isAllowedNavigationUri(nextUri)) {
              _showSnackBar('已阻止跳转到站外页面');
              return NavigationDecision.prevent;
            }

            _setPendingLocation(nextUri ?? _currentUri);
            return NavigationDecision.navigate;
          },
          onPageStarted: (String url) {
            _startLoading(
              AppConfig.rewriteToCurrentHost(Uri.tryParse(url) ?? _currentUri),
              preserveCurrentPage:
                  _pendingPageLoad?.intent == NavigationIntent.preserve,
            );
          },
          onPageFinished: (String url) async {
            final int loadId = _activeLoadId;
            try {
              await _controller.runJavaScript(
                buildPageExtractionScript(loadId),
              );
            } catch (_) {
              if (!mounted || loadId != _activeLoadId) {
                return;
              }
              _failPendingPageLoad('頁面已加載，但轉換內容失敗。');
            }
          },
          onUrlChange: (UrlChange change) {
            if (change.url == null) {
              return;
            }
            _setPendingLocation(Uri.tryParse(change.url!) ?? _currentUri);
          },
          onWebResourceError: (WebResourceError error) {
            if (error.isForMainFrame == false) {
              return;
            }
            unawaited(
              _handleMainFrameFailure(
                error.description.isEmpty ? '頁面加載失敗，請稍後重試。' : error.description,
              ),
            );
          },
        ),
      );
  }

  WebViewController _buildDownloadController() {
    return WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(AppConfig.desktopUserAgent)
      ..addJavaScriptChannel(
        'easyCopyBridge',
        onMessageReceived: _handleDownloadBridgeMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            final Uri? nextUri = Uri.tryParse(request.url);
            if (!AppConfig.isAllowedNavigationUri(nextUri)) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageFinished: (String _) async {
            final int loadId = _downloadActiveLoadId;
            if (_downloadExtractionCompleter == null) {
              return;
            }
            try {
              await _downloadController.runJavaScript(
                buildPageExtractionScript(loadId),
              );
            } catch (error) {
              _downloadExtractionCompleter?.completeError(error);
              _downloadExtractionCompleter = null;
            }
          },
          onWebResourceError: (WebResourceError error) {
            if (error.isForMainFrame == false) {
              return;
            }
            _downloadExtractionCompleter?.completeError(
              error.description.isEmpty ? '章节解析失败' : error.description,
            );
            _downloadExtractionCompleter = null;
          },
        ),
      );
  }

  void _handleBridgeMessage(JavaScriptMessage message) {
    final _PendingPageLoad? pendingLoad = _pendingPageLoad;
    if (pendingLoad == null || pendingLoad.completer.isCompleted) {
      return;
    }
    try {
      final Object? decoded = jsonDecode(message.message);
      if (decoded is! Map) {
        return;
      }

      final Map<String, Object?> payload = decoded.map(
        (Object? key, Object? value) => MapEntry(key.toString(), value),
      );

      final int loadId = (payload['loadId'] as num?)?.toInt() ?? -1;
      if (loadId != _activeLoadId || loadId != pendingLoad.loadId) {
        return;
      }

      payload.remove('loadId');
      final EasyCopyPage page = PageCacheStore.restorePagePayload(payload);
      _consecutiveFrameFailures = 0;
      _applyLoadedPage(
        page,
        targetTabIndex: pendingLoad.targetTabIndex,
        switchToTab: _selectedIndex == pendingLoad.targetTabIndex,
      );
      pendingLoad.completer.complete(page);
      _pendingPageLoad = null;
    } catch (_) {
      _failPendingPageLoad('轉換資料解析失敗。');
    }
  }

  void _handleDownloadBridgeMessage(JavaScriptMessage message) {
    final Completer<ReaderPageData>? completer = _downloadExtractionCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }

    try {
      final Object? decoded = jsonDecode(message.message);
      if (decoded is! Map) {
        return;
      }

      final Map<String, Object?> payload = decoded.map(
        (Object? key, Object? value) => MapEntry(key.toString(), value),
      );
      final int loadId = (payload['loadId'] as num?)?.toInt() ?? -1;
      if (loadId != _downloadActiveLoadId) {
        return;
      }

      payload.remove('loadId');
      final EasyCopyPage page = PageCacheStore.restorePagePayload(payload);
      if (page is ReaderPageData) {
        completer.complete(page);
      } else {
        completer.completeError('章节解析失败');
      }
    } catch (error) {
      completer.completeError(error);
    } finally {
      _downloadExtractionCompleter = null;
    }
  }

  Future<void> _refreshCachedComics() async {
    final List<CachedComicLibraryEntry> comics = await _downloadService
        .loadCachedLibrary();
    if (!mounted) {
      _cachedComics = comics;
      _isLoadingCachedComics = false;
      return;
    }
    setState(() {
      _cachedComics = comics;
      _isLoadingCachedComics = false;
    });
  }

  Future<ReaderPageData> _extractReaderPageForDownload(Uri uri) async {
    if (_downloadExtractionCompleter != null) {
      throw StateError('正在准备其他章节下载，请稍后再试。');
    }
    await _syncSessionCookiesToCurrentHost();
    final Completer<ReaderPageData> completer = Completer<ReaderPageData>();
    _downloadExtractionCompleter = completer;
    _downloadActiveLoadId += 1;
    await _downloadController.loadRequest(AppConfig.rewriteToCurrentHost(uri));
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _downloadExtractionCompleter = null;
        throw TimeoutException('章节解析超时');
      },
    );
  }

  DownloadQueueSnapshot get _downloadQueueSnapshot =>
      _downloadQueueSnapshotNotifier.value;

  Future<void> _restoreDownloadQueue() async {
    _downloadQueueSnapshotNotifier.value = await _downloadQueueStore.read();
  }

  Future<void> _persistDownloadQueueSnapshot(
    DownloadQueueSnapshot snapshot,
  ) async {
    _downloadQueueSnapshotNotifier.value = snapshot;
    if (snapshot.isEmpty) {
      await _downloadQueueStore.clear();
      return;
    }
    await _downloadQueueStore.write(snapshot);
  }

  void _setDownloadQueueSnapshotInMemory(DownloadQueueSnapshot snapshot) {
    _downloadQueueSnapshotNotifier.value = snapshot;
  }

  DownloadQueueTask? _downloadQueueTaskById(String taskId) {
    for (final DownloadQueueTask task in _downloadQueueSnapshot.tasks) {
      if (task.id == taskId) {
        return task;
      }
    }
    return null;
  }

  Future<void> _updateDownloadQueueTask(
    DownloadQueueTask updatedTask, {
    bool persist = true,
  }) async {
    final DownloadQueueSnapshot snapshot = _downloadQueueSnapshot;
    final int index = snapshot.tasks.indexWhere(
      (DownloadQueueTask task) => task.id == updatedTask.id,
    );
    if (index == -1) {
      return;
    }

    final List<DownloadQueueTask> tasks = snapshot.tasks.toList(growable: true);
    tasks[index] = updatedTask;
    final DownloadQueueSnapshot nextSnapshot = snapshot.copyWith(
      tasks: tasks.toList(growable: false),
    );
    if (persist) {
      await _persistDownloadQueueSnapshot(nextSnapshot);
      return;
    }
    _setDownloadQueueSnapshotInMemory(nextSnapshot);
  }

  String _comicQueueKey(String value) {
    final Uri? uri = Uri.tryParse(value);
    if (uri == null) {
      return value.trim();
    }
    return Uri(path: AppConfig.rewriteToCurrentHost(uri).path).toString();
  }

  DownloadQueueTask _buildDownloadQueueTask(
    DetailPageData page,
    Uri chapterUri,
    ChapterData chapter,
  ) {
    final DateTime now = DateTime.now();
    final String comicKey = _comicQueueKey(page.uri);
    final String chapterKey = _chapterPathKey(chapterUri.toString());
    final String id = sha1
        .convert(utf8.encode('$comicKey::$chapterKey'))
        .toString();
    return DownloadQueueTask(
      id: id,
      comicKey: comicKey,
      chapterKey: chapterKey,
      comicTitle: page.title,
      comicUri: page.uri,
      coverUrl: page.coverUrl,
      chapterLabel: chapter.label,
      chapterHref: chapterUri.toString(),
      status: DownloadQueueTaskStatus.queued,
      progressLabel: '等待缓存',
      completedImages: 0,
      totalImages: 0,
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> _enqueueSelectedChapters(
    DetailPageData page,
    List<ChapterData> chapters,
  ) async {
    final DownloadQueueSnapshot snapshot = _downloadQueueSnapshot;
    final List<DownloadQueueTask> tasks = snapshot.tasks.toList(growable: true);
    final Set<String> downloadedKeys = _downloadedChapterPathKeysForDetail(
      page,
    );
    final Set<String> queuedChapterKeys = snapshot.tasks
        .map((DownloadQueueTask task) => task.chapterKey)
        .toSet();
    final Uri detailUri = Uri.parse(page.uri);

    int addedCount = 0;
    int skippedCachedCount = 0;
    int skippedQueuedCount = 0;

    for (final ChapterData chapter in chapters) {
      final Uri chapterUri = AppConfig.resolveNavigationUri(
        chapter.href,
        currentUri: detailUri,
      );
      final String chapterKey = _chapterPathKey(chapterUri.toString());
      if (downloadedKeys.contains(chapterKey)) {
        skippedCachedCount += 1;
        continue;
      }
      if (queuedChapterKeys.contains(chapterKey)) {
        skippedQueuedCount += 1;
        continue;
      }

      tasks.add(_buildDownloadQueueTask(page, chapterUri, chapter));
      queuedChapterKeys.add(chapterKey);
      addedCount += 1;
    }

    if (addedCount == 0) {
      if (skippedCachedCount > 0 && skippedQueuedCount > 0) {
        _showSnackBar('所选章节已缓存或已在队列中');
      } else if (skippedCachedCount > 0) {
        _showSnackBar('所选章节都已经缓存过了');
      } else {
        _showSnackBar('所选章节已在后台缓存队列中');
      }
      return;
    }

    final bool keepPaused = snapshot.isPaused && snapshot.isNotEmpty;
    await _persistDownloadQueueSnapshot(
      snapshot.copyWith(
        isPaused: keepPaused,
        tasks: tasks.toList(growable: false),
      ),
    );

    final StringBuffer message = StringBuffer('已加入后台缓存队列：$addedCount 话');
    if (skippedCachedCount > 0) {
      message.write('，已跳过已缓存 $skippedCachedCount 话');
    }
    if (skippedQueuedCount > 0) {
      message.write('，已跳过队列内 $skippedQueuedCount 话');
    }
    if (keepPaused) {
      message.write('（当前队列已暂停）');
    }
    _showSnackBar(message.toString());

    if (!keepPaused) {
      unawaited(_ensureDownloadQueueRunning());
    }
  }

  Future<void> _pauseDownloadQueue() async {
    final DownloadQueueSnapshot snapshot = _downloadQueueSnapshot;
    if (snapshot.isEmpty || snapshot.isPaused) {
      return;
    }
    await _persistDownloadQueueSnapshot(snapshot.copyWith(isPaused: true));
    _showSnackBar('后台缓存将在当前图片完成后暂停');
  }

  Future<void> _resumeDownloadQueue() async {
    final DownloadQueueSnapshot snapshot = _downloadQueueSnapshot;
    if (snapshot.isEmpty) {
      return;
    }

    final DateTime now = DateTime.now();
    final List<DownloadQueueTask> tasks = snapshot.tasks
        .map((DownloadQueueTask task) {
          if (task.status == DownloadQueueTaskStatus.failed ||
              task.status == DownloadQueueTaskStatus.paused ||
              task.status == DownloadQueueTaskStatus.parsing ||
              task.status == DownloadQueueTaskStatus.downloading) {
            return task.copyWith(
              status: DownloadQueueTaskStatus.queued,
              progressLabel: '等待缓存',
              errorMessage: '',
              updatedAt: now,
            );
          }
          return task;
        })
        .toList(growable: false);

    await _persistDownloadQueueSnapshot(
      snapshot.copyWith(isPaused: false, tasks: tasks),
    );
    _showSnackBar('已继续后台缓存');
    unawaited(_ensureDownloadQueueRunning());
  }

  Future<void> _removeComicFromDownloadQueue(
    String comicKey, {
    required String comicTitle,
    bool markFilesForDeletion = false,
  }) async {
    final DownloadQueueSnapshot snapshot = _downloadQueueSnapshot;
    if (snapshot.isEmpty) {
      return;
    }

    final bool containsComic = snapshot.tasks.any(
      (DownloadQueueTask task) => task.comicKey == comicKey,
    );
    if (!containsComic) {
      return;
    }

    final bool removesActiveComic = snapshot.activeTask?.comicKey == comicKey;
    final List<DownloadQueueTask> remainingTasks = snapshot.tasks
        .where((DownloadQueueTask task) => task.comicKey != comicKey)
        .toList(growable: false);

    if (removesActiveComic) {
      _cancelledComicKeys.add(comicKey);
      if (markFilesForDeletion) {
        _cancelledComicTitles[comicKey] = comicTitle;
      }
    }

    await _persistDownloadQueueSnapshot(
      snapshot.copyWith(
        isPaused: remainingTasks.isEmpty ? false : snapshot.isPaused,
        tasks: remainingTasks,
      ),
    );
  }

  Future<void> _confirmDeleteCachedComic(CachedComicLibraryEntry item) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('删除已缓存漫画'),
          content: Text('确认删除《${item.comicTitle}》的本地缓存吗？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }

    final String comicKey = item.comicHref.isEmpty
        ? item.comicTitle
        : _comicQueueKey(item.comicHref);
    final bool removesActiveComic =
        _downloadQueueSnapshot.activeTask?.comicKey == comicKey;

    await _removeComicFromDownloadQueue(
      comicKey,
      comicTitle: item.comicTitle,
      markFilesForDeletion: removesActiveComic,
    );

    if (!removesActiveComic) {
      await _downloadService.deleteCachedComic(item);
      await _refreshCachedComics();
    }

    _showSnackBar('已删除 ${item.comicTitle} 的缓存');
  }

  Future<void> _confirmRemoveQueuedComic(DownloadQueueTask task) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('移出缓存队列'),
          content: Text('确认停止《${task.comicTitle}》的后台缓存，并清理未完成文件吗？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('移出'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }

    final bool removesActiveComic =
        _downloadQueueSnapshot.activeTask?.comicKey == task.comicKey;
    await _removeComicFromDownloadQueue(
      task.comicKey,
      comicTitle: task.comicTitle,
      markFilesForDeletion: true,
    );
    if (!removesActiveComic) {
      await _downloadService.deleteComicCacheByTitle(task.comicTitle);
      await _refreshCachedComics();
    }
    _showSnackBar('已移出 ${task.comicTitle} 的缓存任务');
  }

  bool _shouldPauseActiveDownload(DownloadQueueTask task) {
    return _downloadQueueSnapshot.isPaused &&
        _downloadQueueTaskById(task.id) != null;
  }

  bool _shouldCancelActiveDownload(DownloadQueueTask task) {
    return _cancelledComicKeys.contains(task.comicKey) ||
        _downloadQueueTaskById(task.id) == null;
  }

  Future<void> _ensureDownloadQueueRunning() async {
    if (_isProcessingDownloadQueue ||
        _downloadQueueSnapshot.isPaused ||
        _downloadQueueSnapshot.isEmpty ||
        !mounted) {
      return;
    }

    _isProcessingDownloadQueue = true;
    try {
      while (mounted) {
        final DownloadQueueSnapshot snapshot = _downloadQueueSnapshot;
        if (snapshot.isPaused || snapshot.isEmpty) {
          break;
        }
        final DownloadQueueTask task = snapshot.activeTask!;
        await _runDownloadQueueTask(task);
      }
    } finally {
      _isProcessingDownloadQueue = false;
    }
  }

  Future<void> _runDownloadQueueTask(DownloadQueueTask task) async {
    await _updateDownloadQueueTask(
      task.copyWith(
        status: DownloadQueueTaskStatus.parsing,
        progressLabel: '正在解析 ${task.chapterLabel}',
        completedImages: 0,
        totalImages: 0,
        errorMessage: '',
        updatedAt: DateTime.now(),
      ),
    );

    try {
      await _session.ensureInitialized();
      final ReaderPageData readerPage = await _extractReaderPageForDownload(
        Uri.parse(task.chapterHref),
      );

      if (_shouldCancelActiveDownload(task)) {
        throw const DownloadCancelledException();
      }
      if (_shouldPauseActiveDownload(task)) {
        throw const DownloadPausedException();
      }

      await _updateDownloadQueueTask(
        task.copyWith(
          status: DownloadQueueTaskStatus.downloading,
          progressLabel: '正在缓存 ${task.chapterLabel}',
          completedImages: 0,
          totalImages: readerPage.imageUrls.length,
          errorMessage: '',
          updatedAt: DateTime.now(),
        ),
      );

      await _downloadService.downloadChapter(
        readerPage,
        cookieHeader: _session.cookieHeader,
        comicUri: task.comicUri,
        chapterHref: task.chapterHref,
        chapterLabel: task.chapterLabel,
        coverUrl: task.coverUrl,
        shouldPause: () => _shouldPauseActiveDownload(task),
        shouldCancel: () => _shouldCancelActiveDownload(task),
        onProgress: (ChapterDownloadProgress progress) async {
          final DownloadQueueTask? latestTask = _downloadQueueTaskById(task.id);
          if (latestTask == null) {
            return;
          }
          await _updateDownloadQueueTask(
            latestTask.copyWith(
              status: DownloadQueueTaskStatus.downloading,
              progressLabel: '${task.chapterLabel} · ${progress.currentLabel}',
              completedImages: progress.completedCount,
              totalImages: progress.totalCount,
              errorMessage: '',
              updatedAt: DateTime.now(),
            ),
            persist: false,
          );
        },
      );

      final DownloadQueueSnapshot snapshot = _downloadQueueSnapshot;
      final List<DownloadQueueTask> remainingTasks = snapshot.tasks
          .where((DownloadQueueTask item) => item.id != task.id)
          .toList(growable: false);
      await _persistDownloadQueueSnapshot(
        snapshot.copyWith(
          isPaused: remainingTasks.isEmpty ? false : snapshot.isPaused,
          tasks: remainingTasks,
        ),
      );
      await _refreshCachedComics();

      if (mounted && remainingTasks.isEmpty) {
        _showSnackBar('后台缓存已完成');
      }
    } on DownloadPausedException {
      final DownloadQueueTask? latestTask = _downloadQueueTaskById(task.id);
      if (latestTask != null) {
        final String pauseLabel =
            latestTask.totalImages > 0 && latestTask.completedImages > 0
            ? '已暂停 ${latestTask.completedImages}/${latestTask.totalImages}'
            : '已暂停';
        await _updateDownloadQueueTask(
          latestTask.copyWith(
            status: DownloadQueueTaskStatus.paused,
            progressLabel: pauseLabel,
            updatedAt: DateTime.now(),
          ),
        );
      }
    } on DownloadCancelledException {
      final String comicTitle =
          _cancelledComicTitles.remove(task.comicKey) ?? task.comicTitle;
      _cancelledComicKeys.remove(task.comicKey);
      await _downloadService.deleteComicCacheByTitle(comicTitle);
      await _refreshCachedComics();
    } catch (error) {
      final DownloadQueueTask? latestTask = _downloadQueueTaskById(task.id);
      final String message = _formatDownloadError(error);
      if (latestTask != null) {
        final DownloadQueueSnapshot snapshot = _downloadQueueSnapshot;
        final List<DownloadQueueTask> tasks = snapshot.tasks
            .map((DownloadQueueTask item) {
              if (item.id != latestTask.id) {
                return item;
              }
              return latestTask.copyWith(
                status: DownloadQueueTaskStatus.failed,
                progressLabel: '失败：$message',
                errorMessage: message,
                updatedAt: DateTime.now(),
              );
            })
            .toList(growable: false);
        await _persistDownloadQueueSnapshot(
          snapshot.copyWith(isPaused: true, tasks: tasks),
        );
      }
      if (mounted) {
        _showSnackBar('缓存失败：$message');
      }
    }
  }

  String _formatDownloadError(Object error) {
    return switch (error) {
      TimeoutException _ => '章节解析超时',
      HttpException httpError => httpError.message,
      FileSystemException fileError => fileError.message,
      DownloadPausedException paused => paused.message,
      DownloadCancelledException cancelled => cancelled.message,
      _ => error.toString(),
    };
  }

  void _setPendingLocation(Uri uri) {
    final Uri rewrittenUri = AppConfig.rewriteToCurrentHost(uri);
    final int tabIndex =
        _pendingPageLoad?.targetTabIndex ?? tabIndexForUri(rewrittenUri);
    _mutateSessionState(() {
      _tabSessionStore.replaceCurrent(tabIndex, rewrittenUri);
    }, syncSearch: tabIndex == _selectedIndex);
  }

  void _startLoading(Uri uri, {required bool preserveCurrentPage}) {
    if (!preserveCurrentPage) {
      _resetStandardScrollPosition();
    }
    final Uri rewrittenUri = AppConfig.rewriteToCurrentHost(uri);
    final int tabIndex =
        _pendingPageLoad?.targetTabIndex ?? tabIndexForUri(rewrittenUri);
    final EasyCopyPage? visiblePage = preserveCurrentPage
        ? _tabSessionStore.currentEntry(tabIndex).page
        : null;
    _mutateSessionState(() {
      _tabSessionStore.replaceCurrent(tabIndex, rewrittenUri);
      _tabSessionStore.updateCurrent(
        tabIndex,
        (PrimaryTabRouteEntry entry) => entry.copyWith(
          uri: rewrittenUri,
          page: visiblePage,
          clearPage: !preserveCurrentPage,
          isLoading: true,
          clearError: true,
          standardScrollOffset: preserveCurrentPage
              ? entry.standardScrollOffset
              : 0,
        ),
      );
    }, syncSearch: tabIndex == _selectedIndex);
  }

  int _prepareRouteEntry(
    Uri uri, {
    required NavigationIntent intent,
    required bool preserveVisiblePage,
  }) {
    final Uri targetUri = AppConfig.rewriteToCurrentHost(uri);
    final int tabIndex = tabIndexForUri(targetUri);
    final EasyCopyPage? preservedPage = preserveVisiblePage
        ? _tabSessionStore.currentEntry(tabIndex).page
        : null;
    _mutateSessionState(() {
      switch (intent) {
        case NavigationIntent.push:
          _tabSessionStore.push(tabIndex, targetUri);
          break;
        case NavigationIntent.preserve:
          _tabSessionStore.replaceCurrent(tabIndex, targetUri);
          break;
        case NavigationIntent.resetToRoot:
          _tabSessionStore.resetToRoot(tabIndex);
          _tabSessionStore.replaceCurrent(tabIndex, targetUri);
          break;
      }
      _selectedIndex = tabIndex;
      _tabSessionStore.updateCurrent(
        tabIndex,
        (PrimaryTabRouteEntry entry) => entry.copyWith(
          uri: targetUri,
          page: preservedPage,
          clearPage: !preserveVisiblePage,
          isLoading: true,
          clearError: true,
          standardScrollOffset: preserveVisiblePage
              ? entry.standardScrollOffset
              : 0,
        ),
      );
    });
    return tabIndex;
  }

  void _markTabEntryLoading(int tabIndex, {required bool preservePage}) {
    _mutateSessionState(() {
      _tabSessionStore.updateCurrent(
        tabIndex,
        (PrimaryTabRouteEntry entry) => entry.copyWith(
          isLoading: true,
          clearError: true,
          clearPage: !preservePage,
        ),
      );
    }, syncSearch: tabIndex == _selectedIndex);
  }

  void _finishTabEntryLoading(int tabIndex, {String? message}) {
    _mutateSessionState(() {
      _tabSessionStore.updateCurrent(
        tabIndex,
        (PrimaryTabRouteEntry entry) => entry.copyWith(
          isLoading: false,
          errorMessage: message,
          clearError: message == null,
        ),
      );
    }, syncSearch: tabIndex == _selectedIndex);
  }

  Future<EasyCopyPage> _loadStandardPageFresh(
    Uri uri, {
    required String authScope,
  }) async {
    final Uri targetUri = AppConfig.rewriteToCurrentHost(uri);
    final int loadId = ++_activeLoadId;
    final _PendingPageLoad pendingLoad = _PendingPageLoad(
      requestedUri: targetUri,
      queryKey: _pageQueryKeyForUri(targetUri, authScope: authScope),
      intent: _nextFreshNavigationIntent ?? NavigationIntent.preserve,
      loadId: loadId,
      targetTabIndex: tabIndexForUri(targetUri),
      completer: Completer<EasyCopyPage>(),
    );
    _nextFreshNavigationIntent = null;
    _pendingPageLoad = pendingLoad;
    await _syncSessionCookiesToCurrentHost();
    await _controller.loadRequest(targetUri);
    return pendingLoad.completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        if (identical(_pendingPageLoad, pendingLoad)) {
          _pendingPageLoad = null;
        }
        throw TimeoutException('页面解析超时');
      },
    );
  }

  void _applyLoadedPage(
    EasyCopyPage page, {
    int? targetTabIndex,
    bool switchToTab = true,
  }) {
    final Uri pageUri = AppConfig.rewriteToCurrentHost(Uri.parse(page.uri));
    final int tabIndex = targetTabIndex ?? tabIndexForUri(pageUri);
    final String? previousReaderUri =
        tabIndex == _selectedIndex && _page is ReaderPageData
        ? (_page as ReaderPageData).uri
        : null;

    _mutateSessionState(() {
      if (switchToTab) {
        _selectedIndex = tabIndex;
      }
      _tabSessionStore.updatePage(tabIndex, page);
    }, syncSearch: switchToTab || tabIndex == _selectedIndex);

    if (tabIndex != _selectedIndex) {
      return;
    }
    if (page is ReaderPageData) {
      _handleReaderPageLoaded(page, previousUri: previousReaderUri);
      return;
    }
    _restoreStandardScrollPosition(
      _tabSessionStore.currentEntry(tabIndex).standardScrollOffset,
    );
  }

  void _failPendingPageLoad(String message) {
    final _PendingPageLoad? pendingLoad = _pendingPageLoad;
    if (pendingLoad == null) {
      return;
    }
    if (!pendingLoad.completer.isCompleted) {
      pendingLoad.completer.completeError(message);
    }
    _pendingPageLoad = null;

    final PrimaryTabRouteEntry currentEntry = _tabSessionStore.currentEntry(
      pendingLoad.targetTabIndex,
    );
    if (currentEntry.page != null) {
      _finishTabEntryLoading(pendingLoad.targetTabIndex);
      if (pendingLoad.targetTabIndex == _selectedIndex) {
        _showSnackBar(message);
      }
      return;
    }
    _mutateSessionState(() {
      _tabSessionStore.updateError(
        pendingLoad.targetTabIndex,
        currentEntry.routeKey,
        message,
      );
    }, syncSearch: pendingLoad.targetTabIndex == _selectedIndex);
  }

  Future<void> _loadUri(
    Uri uri, {
    bool bypassCache = false,
    bool preserveVisiblePage = false,
    NavigationIntent historyMode = NavigationIntent.push,
  }) async {
    _persistVisiblePageState();
    await _hostManager.ensureInitialized();
    final Uri targetUri = AppConfig.rewriteToCurrentHost(uri);
    final PageQueryKey key = _pageQueryKeyForUri(targetUri);
    if (!bypassCache &&
        !preserveVisiblePage &&
        !_isLoading &&
        _page != null &&
        _currentEntry.routeKey == key.routeKey &&
        _isPrimaryTabContent) {
      _restoreStandardScrollPosition(_currentEntry.standardScrollOffset);
      return;
    }
    if (!preserveVisiblePage) {
      _resetStandardScrollPosition();
    }
    if (_isLoginUri(targetUri)) {
      await _openAuthFlow();
      return;
    }
    if (_isProfileUri(targetUri)) {
      await _loadProfilePage(
        forceRefresh: bypassCache,
        historyMode: historyMode,
        preserveVisiblePage: preserveVisiblePage,
      );
      return;
    }
    if (!AppConfig.isAllowedNavigationUri(targetUri)) {
      _showSnackBar('已阻止跳转到站外页面');
      return;
    }

    _consecutiveFrameFailures = 0;
    final int targetTabIndex = _prepareRouteEntry(
      targetUri,
      intent: historyMode,
      preserveVisiblePage: preserveVisiblePage,
    );
    if (!bypassCache) {
      final CachedPageHit? cachedHit = await _pageRepository.readCached(key);
      if (cachedHit != null) {
        _applyLoadedPage(
          cachedHit.page,
          targetTabIndex: targetTabIndex,
          switchToTab: true,
        );
        if (!cachedHit.envelope.isSoftExpired(DateTime.now())) {
          return;
        }
        _markTabEntryLoading(targetTabIndex, preservePage: true);
        unawaited(
          _revalidateCachedPage(
            targetUri,
            key: key,
            cachedEntry: cachedHit.envelope,
            targetTabIndex: targetTabIndex,
          ),
        );
        return;
      }
    }

    _nextFreshNavigationIntent = historyMode;
    try {
      await _pageRepository.loadFresh(targetUri, authScope: key.authScope);
    } catch (error) {
      await _handlePageLoadFailure(
        error,
        targetTabIndex: targetTabIndex,
        routeKey: key.routeKey,
      );
    }
  }

  Future<void> _revalidateCachedPage(
    Uri uri, {
    required PageQueryKey key,
    required CachedPageEnvelope cachedEntry,
    required int targetTabIndex,
  }) async {
    try {
      await _pageRepository.revalidate(uri, key: key, envelope: cachedEntry);
      final PrimaryTabRouteEntry entry = _tabSessionStore.currentEntry(
        targetTabIndex,
      );
      if (entry.routeKey != key.routeKey) {
        return;
      }
      final CachedPageHit? refreshedHit = await _pageRepository.readCached(key);
      if (refreshedHit != null) {
        _applyLoadedPage(
          refreshedHit.page,
          targetTabIndex: targetTabIndex,
          switchToTab: targetTabIndex == _selectedIndex,
        );
        return;
      }
      _finishTabEntryLoading(targetTabIndex);
    } catch (_) {
      _finishTabEntryLoading(targetTabIndex);
    }
  }

  Future<void> _loadProfilePage({
    bool forceRefresh = false,
    bool preserveVisiblePage = false,
    NavigationIntent historyMode = NavigationIntent.push,
  }) async {
    _persistVisiblePageState();
    if (!preserveVisiblePage) {
      _resetStandardScrollPosition();
    }
    final Uri profileUri = AppConfig.profileUri;
    final int targetTabIndex = _prepareRouteEntry(
      profileUri,
      intent: historyMode,
      preserveVisiblePage: preserveVisiblePage,
    );
    final PageQueryKey key = _pageQueryKeyForUri(profileUri);
    if (!forceRefresh) {
      final CachedPageHit? cachedHit = await _pageRepository.readCached(key);
      if (cachedHit != null) {
        _applyLoadedPage(
          cachedHit.page,
          targetTabIndex: targetTabIndex,
          switchToTab: true,
        );
        if (!cachedHit.envelope.isSoftExpired(DateTime.now())) {
          return;
        }
        _markTabEntryLoading(targetTabIndex, preservePage: true);
        unawaited(
          _revalidateCachedPage(
            profileUri,
            key: key,
            cachedEntry: cachedHit.envelope,
            targetTabIndex: targetTabIndex,
          ),
        );
        return;
      }
    }

    try {
      final EasyCopyPage profilePage = await _pageRepository.loadFresh(
        profileUri,
        authScope: key.authScope,
      );
      _applyLoadedPage(
        profilePage,
        targetTabIndex: targetTabIndex,
        switchToTab: true,
      );
    } catch (error) {
      await _handlePageLoadFailure(
        error,
        targetTabIndex: targetTabIndex,
        routeKey: key.routeKey,
      );
    }
  }

  Future<void> _handlePageLoadFailure(
    Object error, {
    required int targetTabIndex,
    required String routeKey,
  }) async {
    final String message = error.toString();
    if (message.contains('登录已失效')) {
      await _logout(showFeedback: false);
      if (targetTabIndex == _selectedIndex) {
        _showSnackBar('登录已失效，请重新登录。');
      }
      return;
    }

    final PrimaryTabRouteEntry entry = _tabSessionStore.currentEntry(
      targetTabIndex,
    );
    if (entry.page != null) {
      _finishTabEntryLoading(targetTabIndex);
      if (targetTabIndex == _selectedIndex) {
        _showSnackBar(message);
      }
      return;
    }

    _mutateSessionState(() {
      _tabSessionStore.updateError(targetTabIndex, routeKey, message);
    }, syncSearch: targetTabIndex == _selectedIndex);
  }

  Future<void> _retryCurrentPage() async {
    if (_page is ProfilePageData || _selectedIndex == 3) {
      await _loadProfilePage(
        forceRefresh: true,
        preserveVisiblePage: _page != null,
        historyMode: NavigationIntent.preserve,
      );
      return;
    }
    await _loadUri(
      _currentUri,
      bypassCache: true,
      preserveVisiblePage: _page != null,
      historyMode: NavigationIntent.preserve,
    );
  }

  Future<void> _loadHome() async {
    await _loadUri(
      _targetUriForPrimaryTab(0, resetToRoot: true),
      preserveVisiblePage: true,
      historyMode: NavigationIntent.resetToRoot,
    );
  }

  void _navigateDiscoverFilter(String href) {
    if (href.trim().isEmpty) {
      return;
    }
    unawaited(
      _loadUri(
        AppConfig.resolveNavigationUri(href, currentUri: _currentUri),
        preserveVisiblePage: true,
      ),
    );
  }

  void _navigateRankFilter(String href) {
    if (href.trim().isEmpty) {
      return;
    }
    unawaited(
      _loadUri(
        AppConfig.resolveNavigationUri(href, currentUri: _currentUri),
        preserveVisiblePage: true,
      ),
    );
  }

  void _navigateToHref(String href) {
    if (href.trim().isEmpty) {
      return;
    }
    final Uri targetUri = AppConfig.resolveNavigationUri(
      href,
      currentUri: _currentUri,
    );
    if (_isLoginUri(targetUri)) {
      unawaited(_openAuthFlow());
      return;
    }
    unawaited(_loadUri(targetUri));
  }

  Future<void> _openAuthFlow() async {
    await _hostManager.ensureInitialized();
    if (!mounted) {
      return;
    }
    final AuthSessionResult? result = await Navigator.of(context).push(
      MaterialPageRoute<AuthSessionResult>(
        builder: (BuildContext context) {
          return NativeLoginScreen(
            loginUri: AppConfig.resolvePath('/web/login/?url=person/home'),
            userAgent: AppConfig.desktopUserAgent,
          );
        },
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    final String? token = result.cookies['token'];
    if ((token ?? '').isEmpty) {
      return;
    }
    await _session.updateFromCookieHeader(result.cookieHeader);
    await _session.saveToken(token!, cookies: result.cookies);
    await _hostManager.pinSessionHost(_hostManager.currentHost);
    await _syncSessionCookiesToCurrentHost();
    await _loadProfilePage(
      forceRefresh: true,
      historyMode: NavigationIntent.resetToRoot,
    );
  }

  Future<void> _logout({bool showFeedback = true}) async {
    _persistVisiblePageState();
    _resetStandardScrollPosition();
    await _pageRepository.removeAuthenticatedEntries();
    await _session.clear();
    await _hostManager.clearSessionPin();
    await _cookieManager.clearCookies();
    _mutateSessionState(() {
      _selectedIndex = 3;
      _tabSessionStore.resetToRoot(3);
      _tabSessionStore.updatePage(
        3,
        ProfilePageData.loggedOut(uri: AppConfig.profileUri.toString()),
      );
    });
    if (showFeedback) {
      _showSnackBar('已退出登录');
    }
  }

  void _showSnackBar(String message) {
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(
      context,
    );
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  void _syncSearchController() {
    final String query = _currentUri.queryParameters['q'] ?? '';
    if (_searchController.text == query) {
      return;
    }
    _searchController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
  }

  void _submitSearch(String value) {
    final String query = value.trim();
    if (query.isEmpty) {
      return;
    }
    unawaited(_loadUri(AppConfig.buildSearchUri(query)));
  }

  Uri _targetUriForPrimaryTab(int index, {bool resetToRoot = false}) {
    if (resetToRoot) {
      return _tabSessionStore.resetToRoot(index).uri;
    }
    return _tabSessionStore.currentEntry(index).uri;
  }

  Future<void> _onItemTapped(int index) async {
    if (index < 0 || index >= appDestinations.length) {
      return;
    }
    if (index == _selectedIndex && _isPrimaryTabContent && !_isLoading) {
      await _scrollCurrentStandardPageToTop();
      return;
    }
    if (index == 3) {
      await _loadProfilePage(
        preserveVisiblePage: true,
        historyMode: index == _selectedIndex
            ? NavigationIntent.resetToRoot
            : NavigationIntent.preserve,
      );
      return;
    }
    final bool shouldResetToRoot = index == _selectedIndex;
    final Uri targetUri = _targetUriForPrimaryTab(
      index,
      resetToRoot: shouldResetToRoot,
    );
    await _loadUri(
      targetUri,
      preserveVisiblePage: !shouldResetToRoot,
      historyMode: shouldResetToRoot
          ? NavigationIntent.resetToRoot
          : NavigationIntent.preserve,
    );
  }

  Future<void> _handleBackNavigation() async {
    _persistVisiblePageState();
    final PrimaryTabRouteEntry? previousEntry = _tabSessionStore.pop(
      _selectedIndex,
    );
    if (previousEntry != null) {
      await _loadUri(
        previousEntry.uri,
        preserveVisiblePage: _page != null,
        historyMode: NavigationIntent.preserve,
      );
      return;
    }
    if (_selectedIndex != 0) {
      await _loadHome();
      return;
    }
    await SystemNavigator.pop();
  }

  Future<void> _handleMainFrameFailure(String message) async {
    _consecutiveFrameFailures += 1;
    if (!mounted) {
      return;
    }
    if (_pendingPageLoad != null) {
      _failPendingPageLoad(message);
    } else if (_page == null) {
      _mutateSessionState(() {
        _tabSessionStore.updateError(
          _selectedIndex,
          _currentEntry.routeKey,
          message,
        );
      });
    } else {
      _finishTabEntryLoading(_selectedIndex);
      _showSnackBar(message);
    }
    if (_isFailingOver || _consecutiveFrameFailures < 2) {
      return;
    }
    _isFailingOver = true;
    try {
      final String previousHost = _hostManager.currentHost;
      final String nextHost = await _hostManager.failover(
        exclude: <String>[previousHost],
      );
      if (nextHost == previousHost) {
        return;
      }
      await _syncSessionCookiesToCurrentHost();
      if (!mounted) {
        return;
      }
      _showSnackBar('当前入口异常，已切换到备用站点。');
      await _loadUri(
        AppConfig.rewriteToCurrentHost(_currentUri),
        preserveVisiblePage: _page != null,
        historyMode: NavigationIntent.preserve,
      );
      _consecutiveFrameFailures = 0;
    } finally {
      _isFailingOver = false;
    }
  }

  Future<void> _syncSessionCookiesToCurrentHost() async {
    await _session.ensureInitialized();
    if (_session.cookies.isEmpty) {
      return;
    }
    for (final MapEntry<String, String> cookie in _session.cookies.entries) {
      await _cookieManager.setCookie(
        WebViewCookie(
          name: cookie.key,
          value: cookie.value,
          domain: _hostManager.currentHost,
          path: '/',
        ),
      );
    }
  }

  void _handleReaderPageLoaded(ReaderPageData page, {String? previousUri}) {
    unawaited(EasyCopyImageCaches.prefetchReaderImages(page.imageUrls));
    if (previousUri != page.uri) {
      unawaited(_restoreReaderScrollPosition(page));
    }
  }

  Future<void> _restoreReaderScrollPosition(ReaderPageData page) async {
    final String progressKey = _readerProgressKeyForPage(page);
    final double savedOffset =
        await _readerProgressStore.readOffset(progressKey) ?? 0;
    _lastPersistedReaderOffset = savedOffset;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpReaderToOffset(savedOffset, attempts: 10);
    });
  }

  void _jumpReaderToOffset(double offset, {required int attempts}) {
    if (!_readerScrollController.hasClients) {
      if (attempts > 0) {
        Future<void>.delayed(
          const Duration(milliseconds: 250),
          () => _jumpReaderToOffset(offset, attempts: attempts - 1),
        );
      }
      return;
    }

    final double targetOffset = offset < 0 ? 0 : offset;
    final double maxExtent = _readerScrollController.position.maxScrollExtent;
    if (targetOffset > maxExtent && attempts > 0) {
      Future<void>.delayed(
        const Duration(milliseconds: 250),
        () => _jumpReaderToOffset(targetOffset, attempts: attempts - 1),
      );
      return;
    }
    final double clampedOffset = targetOffset.clamp(0, maxExtent).toDouble();
    _readerScrollController.jumpTo(clampedOffset);
  }

  void _handleReaderScroll() {
    final EasyCopyPage? page = _page;
    if (page is! ReaderPageData || !_readerScrollController.hasClients) {
      return;
    }

    final double currentOffset = _readerScrollController.offset;
    if (_lastPersistedReaderOffset != null &&
        (currentOffset - _lastPersistedReaderOffset!).abs() < 48) {
      return;
    }
    _readerProgressDebounce?.cancel();
    _readerProgressDebounce = Timer(
      const Duration(milliseconds: 900),
      _persistCurrentReaderProgress,
    );
  }

  String _readerProgressKeyForPage(ReaderPageData page) {
    final Uri uri = Uri.parse(page.uri);
    return '${uri.path}::${page.contentKey}';
  }

  void _persistCurrentReaderProgress() {
    final EasyCopyPage? page = _page;
    if (page is! ReaderPageData || !_readerScrollController.hasClients) {
      return;
    }
    final double offset = _readerScrollController.offset;
    final String progressKey = _readerProgressKeyForPage(page);
    _lastPersistedReaderOffset = offset;
    unawaited(_readerProgressStore.writeOffset(progressKey, offset));
  }

  void _persistVisiblePageState() {
    _persistCurrentReaderProgress();
    if (_page == null ||
        _isReaderMode ||
        !_standardScrollController.hasClients) {
      return;
    }
    _tabSessionStore.updateScroll(
      _selectedIndex,
      _currentEntry.routeKey,
      _standardScrollController.offset,
    );
  }

  void _handleStandardScroll() {
    if (_suspendStandardScrollTracking ||
        !_standardScrollController.hasClients ||
        _page == null ||
        _isReaderMode) {
      return;
    }
    _tabSessionStore.updateScroll(
      _selectedIndex,
      _currentEntry.routeKey,
      _standardScrollController.offset,
    );
  }

  void _resetStandardScrollPosition() {
    _suspendStandardScrollTracking = true;
    if (_standardScrollController.hasClients) {
      _standardScrollController.jumpTo(0);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _suspendStandardScrollTracking = false;
        return;
      }
      if (!_standardScrollController.hasClients) {
        _suspendStandardScrollTracking = false;
        return;
      }
      if (_standardScrollController.offset != 0) {
        _standardScrollController.jumpTo(0);
      }
      _suspendStandardScrollTracking = false;
    });
  }

  void _restoreStandardScrollPosition(double offset) {
    _suspendStandardScrollTracking = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpStandardToOffset(offset, attempts: 10);
    });
  }

  void _jumpStandardToOffset(double offset, {required int attempts}) {
    if (!mounted) {
      _suspendStandardScrollTracking = false;
      return;
    }
    if (!_standardScrollController.hasClients) {
      if (attempts > 0) {
        Future<void>.delayed(
          const Duration(milliseconds: 120),
          () => _jumpStandardToOffset(offset, attempts: attempts - 1),
        );
        return;
      }
      _suspendStandardScrollTracking = false;
      return;
    }

    final double maxExtent = _standardScrollController.position.maxScrollExtent;
    final double clampedOffset = offset.clamp(0, maxExtent).toDouble();
    if ((offset - clampedOffset).abs() > 1 && attempts > 0) {
      Future<void>.delayed(
        const Duration(milliseconds: 120),
        () => _jumpStandardToOffset(offset, attempts: attempts - 1),
      );
      return;
    }

    _standardScrollController.jumpTo(clampedOffset);
    _suspendStandardScrollTracking = false;
    _tabSessionStore.updateScroll(
      _selectedIndex,
      _currentEntry.routeKey,
      clampedOffset,
    );
  }

  Future<void> _scrollCurrentStandardPageToTop() async {
    if (!_standardScrollController.hasClients) {
      return;
    }
    await _standardScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
    _tabSessionStore.updateScroll(_selectedIndex, _currentEntry.routeKey, 0);
  }

  bool get _isReaderMode => _page is ReaderPageData;

  bool get _isDetailRoute {
    final EasyCopyPage? page = _page;
    if (page is DetailPageData) {
      return true;
    }
    final String path = _currentUri.path.toLowerCase();
    return path.startsWith('/comic/') && !path.startsWith('/comic/chapter');
  }

  bool get _shouldShowSearchBar {
    final EasyCopyPage? page = _page;
    if (page is ProfilePageData || page is DetailPageData) {
      return false;
    }
    return !_isDetailRoute;
  }

  bool get _isPrimaryTabContent {
    if (_shouldShowBackButton) {
      return false;
    }
    final EasyCopyPage? page = _page;
    return page == null ||
        page is HomePageData ||
        page is DiscoverPageData ||
        page is RankPageData ||
        page is ProfilePageData;
  }

  bool get _shouldShowHeaderCard => !_isPrimaryTabContent && !_isDetailRoute;

  bool get _shouldShowStandaloneDiscoverSearch =>
      _isPrimaryTabContent && _selectedIndex == 1;

  bool get _shouldShowBackButton {
    final EasyCopyPage? page = _page;
    if (page is DetailPageData || page is UnknownPageData || _isDetailRoute) {
      return true;
    }
    if ((page is DiscoverPageData || page == null) &&
        _currentUri.path == '/search') {
      return true;
    }
    return false;
  }

  String get _pageTitle {
    final EasyCopyPage? page = _page;
    if (page == null) {
      if (_isDetailRoute) {
        return '漫畫詳情';
      }
      return appDestinations[_selectedIndex].label;
    }
    return page.title;
  }

  bool _isLoginUri(Uri? uri) {
    if (uri == null) {
      return false;
    }
    return uri.path.startsWith('/web/login');
  }

  bool _isProfileUri(Uri uri) {
    return uri.path.startsWith('/person/home');
  }

  bool _isDiscoverMoreCategoryOption(LinkAction option) {
    return option.label.contains('查看全部分類') ||
        option.href.contains('/filter?point=');
  }

  List<LinkAction> _visibleDiscoverThemeOptions(List<LinkAction> options) {
    if (_isDiscoverThemeExpanded || options.length <= 16) {
      return options;
    }
    const int previewCount = 15;
    final List<LinkAction> visible = options
        .take(previewCount)
        .toList(growable: true);
    final int activeIndex = options.indexWhere(
      (LinkAction option) => option.active,
    );
    if (activeIndex >= previewCount) {
      visible.removeLast();
      visible.add(options[activeIndex]);
    }
    return visible;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) {
          return;
        }
        await _handleBackNavigation();
      },
      child: Stack(
        children: <Widget>[
          Positioned(
            left: -8,
            top: -8,
            width: 4,
            height: 4,
            child: IgnorePointer(child: WebViewWidget(controller: _controller)),
          ),
          Positioned(
            left: -16,
            top: -16,
            width: 4,
            height: 4,
            child: IgnorePointer(
              child: WebViewWidget(controller: _downloadController),
            ),
          ),
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: _isReaderMode
                    ? _buildReaderMode(context, _page as ReaderPageData)
                    : _buildStandardMode(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStandardMode(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        destinations: appDestinations
            .map(
              (AppDestination destination) => NavigationDestination(
                icon: Icon(destination.icon),
                label: destination.label,
              ),
            )
            .toList(growable: false),
      ),
      body: SafeArea(
        child: _errorMessage != null && _page == null
            ? _buildErrorState(context)
            : RefreshIndicator(
                onRefresh: _retryCurrentPage,
                child: ListView(
                  controller: _standardScrollController,
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  children: _buildStandardChildren(context),
                ),
              ),
      ),
    );
  }

  List<Widget> _buildStandardChildren(BuildContext context) {
    final List<Widget> children = <Widget>[
      ..._buildStandardTopContent(context),
      _buildDownloadQueueBanner(),
    ];

    if (_page == null) {
      children.addAll(_buildLoadingSections());
      return children;
    }

    final EasyCopyPage page = _page!;
    switch (page) {
      case HomePageData homePage:
        children.addAll(_buildHomeSections(homePage));
      case DiscoverPageData discoverPage:
        children.addAll(_buildDiscoverSections(discoverPage));
      case RankPageData rankPage:
        children.addAll(_buildRankSections(rankPage));
      case DetailPageData detailPage:
        children.addAll(_buildDetailSections(detailPage));
      case ProfilePageData profilePage:
        children.addAll(_buildProfileSections(profilePage));
      case UnknownPageData unknownPage:
        children.addAll(_buildMessageSections(unknownPage.message));
      case ReaderPageData _:
        break;
    }

    return children;
  }

  List<Widget> _buildStandardTopContent(BuildContext context) {
    if (_shouldShowHeaderCard) {
      return <Widget>[
        _buildHeaderCard(
          context,
          title: _pageTitle,
          showBackButton: _shouldShowBackButton,
          showSearchBar: _shouldShowSearchBar,
        ),
        const SizedBox(height: 18),
      ];
    }

    if (_shouldShowStandaloneDiscoverSearch) {
      return <Widget>[
        _buildStandaloneDiscoverSearchBar(context),
        const SizedBox(height: 18),
      ];
    }

    return const <Widget>[];
  }

  Widget _buildStandaloneDiscoverSearchBar(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18)),
      child: _buildSearchField(context),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4E8EE)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.search_rounded, color: colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              onSubmitted: _submitSearch,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                border: InputBorder.none,
                hintText: '搜尋漫畫、作者或題材',
              ),
            ),
          ),
          IconButton(
            onPressed: () => _submitSearch(_searchController.text),
            icon: const Icon(Icons.arrow_forward_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadQueueBanner() {
    return ValueListenableBuilder<DownloadQueueSnapshot>(
      valueListenable: _downloadQueueSnapshotNotifier,
      builder: (BuildContext context, DownloadQueueSnapshot snapshot, Widget? _) {
        if (snapshot.isEmpty || (_selectedIndex == 3 && _isPrimaryTabContent)) {
          return const SizedBox.shrink();
        }

        final DownloadQueueTask activeTask = snapshot.activeTask!;
        final bool isPaused = snapshot.isPaused;
        final String statusLabel = isPaused
            ? (activeTask.progressLabel.isEmpty
                  ? '后台缓存已暂停'
                  : activeTask.progressLabel)
            : activeTask.progressLabel;

        return Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Material(
            color: isPaused ? const Color(0xFFFFF5E8) : const Color(0xFFEAF6F3),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(
                        isPaused
                            ? Icons.pause_circle_rounded
                            : Icons.download_for_offline_rounded,
                        color: isPaused
                            ? const Color(0xFFB86A00)
                            : const Color(0xFF0E8B84),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${activeTask.comicTitle} · 剩余 ${snapshot.remainingCount} 话',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      TextButton(
                        onPressed: isPaused
                            ? _resumeDownloadQueue
                            : _pauseDownloadQueue,
                        child: Text(isPaused ? '继续' : '暂停'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    statusLabel,
                    style: TextStyle(color: Colors.grey.shade700, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(
                    value: activeTask.fraction > 0 ? activeTask.fraction : null,
                    borderRadius: BorderRadius.circular(999),
                    minHeight: 8,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDownloadQueueSection() {
    return ValueListenableBuilder<DownloadQueueSnapshot>(
      valueListenable: _downloadQueueSnapshotNotifier,
      builder:
          (BuildContext context, DownloadQueueSnapshot snapshot, Widget? _) {
            if (snapshot.isEmpty) {
              return const SizedBox.shrink();
            }

            final Map<String, List<DownloadQueueTask>> groupedTasks =
                <String, List<DownloadQueueTask>>{};
            for (final DownloadQueueTask task in snapshot.tasks) {
              groupedTasks
                  .putIfAbsent(task.comicKey, () => <DownloadQueueTask>[])
                  .add(task);
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: _SurfaceBlock(
                title: '缓存任务',
                actionLabel: snapshot.isPaused ? '继续' : '暂停',
                onActionTap: snapshot.isPaused
                    ? _resumeDownloadQueue
                    : _pauseDownloadQueue,
                child: Column(
                  children: groupedTasks.entries
                      .map((MapEntry<String, List<DownloadQueueTask>> entry) {
                        final List<DownloadQueueTask> tasks = entry.value;
                        final DownloadQueueTask displayTask = tasks.first;
                        final bool isActiveComic =
                            snapshot.activeTask?.comicKey ==
                            displayTask.comicKey;
                        final DownloadQueueTask taskForStatus = isActiveComic
                            ? snapshot.activeTask!
                            : displayTask;
                        final String subtitle = isActiveComic
                            ? taskForStatus.progressLabel
                            : '等待缓存 ${tasks.length} 话';

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Material(
                            color: const Color(0xFFF6F7F9),
                            borderRadius: BorderRadius.circular(18),
                            child: ListTile(
                              contentPadding: const EdgeInsets.fromLTRB(
                                16,
                                8,
                                8,
                                8,
                              ),
                              leading: CircleAvatar(
                                backgroundColor: isActiveComic
                                    ? const Color(0xFF0E8B84)
                                    : const Color(0xFFCBD4DE),
                                foregroundColor: Colors.white,
                                child: Text('${tasks.length}'),
                              ),
                              title: Text(
                                displayTask.comicTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              trailing: IconButton(
                                onPressed: () =>
                                    _confirmRemoveQueuedComic(displayTask),
                                icon: const Icon(Icons.delete_outline_rounded),
                              ),
                            ),
                          ),
                        );
                      })
                      .toList(growable: false),
                ),
              ),
            );
          },
    );
  }

  List<Widget> _buildProfileSections(ProfilePageData page) {
    final List<Widget> sections = <Widget>[
      ProfilePageView(
        page: page,
        onAuthenticate: _openAuthFlow,
        onLogout: _logout,
        onOpenComic: _navigateToHref,
        onOpenHistory: (ProfileHistoryItem item) {
          final String targetHref = item.chapterHref.isNotEmpty
              ? item.chapterHref
              : item.comicHref;
          _navigateToHref(targetHref);
        },
        afterContinueReading: _buildCachedComicsSection(),
      ),
    ];

    sections.add(const SizedBox(height: 18));
    sections.add(_buildDownloadQueueSection());
    return sections;
  }

  Widget _buildCachedComicsSection() {
    if (_isLoadingCachedComics) {
      return _SurfaceBlock(
        title: '已缓存漫画',
        child: Row(
          children: const <Widget>[
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('正在读取本地缓存…'),
          ],
        ),
      );
    }

    if (_cachedComics.isEmpty) {
      return _SurfaceBlock(
        title: '已缓存漫画',
        child: const Text('还没有缓存章节，去漫画详情页挑几话下载吧。'),
      );
    }

    return _SurfaceBlock(
      title: '已缓存漫画',
      child: SizedBox(
        height: 218,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _cachedComics.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (BuildContext context, int index) {
            final CachedComicLibraryEntry item = _cachedComics[index];
            return SizedBox(
              width: 144,
              child: _CachedComicCard(
                item: item,
                onTap: item.comicHref.isEmpty
                    ? null
                    : () => _navigateToHref(item.comicHref),
                onDelete: () => _confirmDeleteCachedComic(item),
              ),
            );
          },
        ),
      ),
    );
  }

  Set<String> _downloadedChapterPathKeysForDetail(DetailPageData page) {
    final Uri currentDetailUri = Uri.parse(page.uri);
    final String targetPath = currentDetailUri.path;
    final CachedComicLibraryEntry? match = _cachedComics
        .cast<CachedComicLibraryEntry?>()
        .firstWhere(
          (CachedComicLibraryEntry? item) =>
              item != null && Uri.tryParse(item.comicHref)?.path == targetPath,
          orElse: () => null,
        );
    if (match == null) {
      return const <String>{};
    }
    return match.chapters
        .map(
          (CachedChapterEntry chapter) => _chapterPathKey(chapter.chapterHref),
        )
        .where((String key) => key.isNotEmpty)
        .toSet();
  }

  String _chapterPathKey(String href) {
    final Uri? uri = Uri.tryParse(href);
    if (uri == null) {
      return '';
    }
    return Uri(path: AppConfig.rewriteToCurrentHost(uri).path).toString();
  }

  List<_ChapterPickerSection> _chapterPickerSections(DetailPageData page) {
    if (page.chapterGroups.isNotEmpty) {
      return page.chapterGroups
          .map(
            (ChapterGroupData group) => _ChapterPickerSection(
              label: group.label,
              chapters: group.chapters,
            ),
          )
          .toList(growable: false);
    }
    return <_ChapterPickerSection>[
      _ChapterPickerSection(label: '全部章节', chapters: page.chapters),
    ];
  }

  Future<void> _showDetailDownloadPicker(DetailPageData page) async {
    final List<_ChapterPickerSection> sections = _chapterPickerSections(page);
    final Set<String> downloadedKeys = _downloadedChapterPathKeysForDetail(
      page,
    );
    final List<ChapterData>?
    selectedChapters = await showModalBottomSheet<List<ChapterData>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (BuildContext context) {
        final Set<String> selectedKeys = <String>{};
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            List<ChapterData> selectedChapterValues() {
              return sections
                  .expand((section) => section.chapters)
                  .where(
                    (ChapterData chapter) =>
                        selectedKeys.contains(_chapterPathKey(chapter.href)),
                  )
                  .toList(growable: false);
            }

            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.78,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          const Expanded(
                            child: Text(
                              '选择要缓存的章节',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              setModalState(() {
                                selectedKeys
                                  ..clear()
                                  ..addAll(
                                    sections
                                        .expand((section) => section.chapters)
                                        .map(
                                          (ChapterData chapter) =>
                                              _chapterPathKey(chapter.href),
                                        ),
                                  );
                              });
                            },
                            child: const Text('全选'),
                          ),
                          TextButton(
                            onPressed: () {
                              setModalState(selectedKeys.clear);
                            },
                            child: const Text('清空'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView(
                          shrinkWrap: true,
                          children: sections
                              .expand((section) {
                                return <Widget>[
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      4,
                                      10,
                                      4,
                                      4,
                                    ),
                                    child: Text(
                                      section.label,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  ...section.chapters.map((
                                    ChapterData chapter,
                                  ) {
                                    final String key = _chapterPathKey(
                                      chapter.href,
                                    );
                                    final bool isDownloaded = downloadedKeys
                                        .contains(key);
                                    final bool selected = selectedKeys.contains(
                                      key,
                                    );
                                    return CheckboxListTile(
                                      value: selected,
                                      controlAffinity:
                                          ListTileControlAffinity.leading,
                                      onChanged: (bool? nextValue) {
                                        setModalState(() {
                                          if (nextValue ?? false) {
                                            selectedKeys.add(key);
                                          } else {
                                            selectedKeys.remove(key);
                                          }
                                        });
                                      },
                                      secondary: isDownloaded
                                          ? const Icon(
                                              Icons.check_circle_rounded,
                                              color: Color(0xFF18A558),
                                            )
                                          : null,
                                      title: Text(chapter.label),
                                    );
                                  }),
                                ];
                              })
                              .toList(growable: false),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: selectedKeys.isEmpty
                              ? null
                              : () {
                                  Navigator.of(
                                    context,
                                  ).pop(selectedChapterValues());
                                },
                          child: Text(
                            selectedKeys.isEmpty
                                ? '请选择章节'
                                : '缓存 ${selectedKeys.length} 话',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (selectedChapters == null || selectedChapters.isEmpty || !mounted) {
      return;
    }
    await _enqueueSelectedChapters(page, selectedChapters);
  }

  Widget _buildHeaderCard(
    BuildContext context, {
    required String title,
    required bool showBackButton,
    required bool showSearchBar,
  }) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                if (showBackButton)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: IconButton.filledTonal(
                      onPressed: _handleBackNavigation,
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFF2F5F8),
                        foregroundColor: const Color(0xFF202733),
                      ),
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
                  ),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 22,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF18202A),
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: _retryCurrentPage,
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFF2F5F8),
                    foregroundColor: colorScheme.primary,
                  ),
                  icon: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            if (showSearchBar) ...<Widget>[
              const SizedBox(height: 14),
              _buildSearchField(context),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildLoadingSections() {
    return <Widget>[
      _buildLoadingCard(height: 220),
      const SizedBox(height: 18),
      _buildLoadingCard(height: 176),
      const SizedBox(height: 18),
      _buildLoadingCard(height: 320),
    ];
  }

  Widget _buildLoadingCard({required double height}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const <Widget>[
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在整理可读内容'),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return ListView(
      controller: _standardScrollController,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: <Widget>[
        ..._buildStandardTopContent(context),
        _buildDownloadQueueBanner(),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: <Widget>[
              Icon(
                Icons.cloud_off_rounded,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 14),
              const Text(
                '内容整理失败',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Text(_errorMessage ?? '', textAlign: TextAlign.center),
              const SizedBox(height: 10),
              Text(
                _currentUri.toString(),
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              const SizedBox(height: 20),
              Row(
                children: <Widget>[
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: _loadHome,
                      child: const Text('回到首頁'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _retryCurrentPage,
                      child: const Text('重新整理'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildHomeSections(HomePageData page) {
    final List<Widget> sections = <Widget>[];

    if (page.heroBanners.isNotEmpty) {
      sections.add(
        _SurfaceBlock(
          title: '推薦焦點',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: 220,
              child: ListView.separated(
                padding: EdgeInsets.zero,
                scrollDirection: Axis.horizontal,
                itemCount: page.heroBanners.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (BuildContext context, int index) {
                  final HeroBannerData banner = page.heroBanners[index];
                  return SizedBox(
                    width: 300,
                    child: _HeroBannerCard(
                      banner: banner,
                      onTap: () => _navigateToHref(banner.href),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      sections.add(const SizedBox(height: 18));
    }

    if (page.feature != null) {
      sections.add(
        _FeatureBannerCard(
          banner: page.feature!,
          onTap: () => _navigateToHref(page.feature!.href),
        ),
      );
      sections.add(const SizedBox(height: 18));
    }

    for (final ComicSectionData section in page.sections) {
      sections.add(
        _SurfaceBlock(
          title: section.title,
          actionLabel: section.href.isNotEmpty ? '更多' : null,
          onActionTap: section.href.isNotEmpty
              ? () => _navigateToHref(section.href)
              : null,
          child: _ComicGrid(items: section.items, onTap: _navigateToHref),
        ),
      );
      sections.add(const SizedBox(height: 18));
    }

    return sections;
  }

  List<Widget> _buildDiscoverSections(DiscoverPageData page) {
    final List<Widget> sections = <Widget>[];

    if (page.filters.isNotEmpty) {
      final FilterGroupData primaryGroup = page.filters.first;
      final List<LinkAction> themeOptions = primaryGroup.options
          .where((LinkAction option) => !_isDiscoverMoreCategoryOption(option))
          .toList(growable: false);
      final List<FilterGroupData> secondaryGroups = page.filters
          .skip(1)
          .toList(growable: false);

      sections.add(
        _SurfaceBlock(
          title: '篩選器',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _FilterGroup(
                group: FilterGroupData(
                  label: primaryGroup.label,
                  options: _visibleDiscoverThemeOptions(themeOptions),
                ),
                onTap: _navigateDiscoverFilter,
                actionLabel: _isDiscoverThemeExpanded ? '收起分類' : '查看全部分類',
                onActionTap: () {
                  setState(() {
                    _isDiscoverThemeExpanded = !_isDiscoverThemeExpanded;
                  });
                },
              ),
              if (secondaryGroups.isNotEmpty) ...<Widget>[
                const SizedBox(height: 18),
                Container(height: 1, color: const Color(0xFFE7EBEF)),
                const SizedBox(height: 18),
                ...secondaryGroups.map(
                  (FilterGroupData group) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _FilterGroup(
                      group: group,
                      onTap: _navigateDiscoverFilter,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
      sections.add(const SizedBox(height: 18));
    }

    sections.add(
      _SurfaceBlock(
        title: '內容列表',
        child: _ComicGrid(items: page.items, onTap: _navigateToHref),
      ),
    );
    sections.add(const SizedBox(height: 18));
    sections.add(
      _PagerCard(
        pager: page.pager,
        onPrev: page.pager.hasPrev
            ? () {
                unawaited(
                  _loadUri(
                    AppConfig.resolveNavigationUri(
                      page.pager.prevHref,
                      currentUri: _currentUri,
                    ),
                    preserveVisiblePage: true,
                  ),
                );
              }
            : null,
        onNext: page.pager.hasNext
            ? () {
                unawaited(
                  _loadUri(
                    AppConfig.resolveNavigationUri(
                      page.pager.nextHref,
                      currentUri: _currentUri,
                    ),
                    preserveVisiblePage: true,
                  ),
                );
              }
            : null,
      ),
    );

    return sections;
  }

  List<Widget> _buildRankSections(RankPageData page) {
    final List<Widget> sections = <Widget>[];

    if (page.categories.isNotEmpty || page.periods.isNotEmpty) {
      sections.add(
        _SurfaceBlock(
          title: '榜單切換',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (page.categories.isNotEmpty)
                _RankFilterGroup(
                  label: '榜單類型',
                  helperText: '切換不同分類榜單',
                  icon: Icons.grid_view_rounded,
                  items: page.categories,
                  onTap: _navigateRankFilter,
                ),
              if (page.categories.isNotEmpty && page.periods.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Container(height: 1, color: const Color(0xFFE7EBEF)),
                ),
              if (page.periods.isNotEmpty)
                _RankFilterGroup(
                  label: '統計週期',
                  helperText: '查看不同時間範圍',
                  icon: Icons.schedule_rounded,
                  items: page.periods,
                  onTap: _navigateRankFilter,
                ),
            ],
          ),
        ),
      );
      sections.add(const SizedBox(height: 18));
    }

    sections.add(
      _SurfaceBlock(
        title: '榜单列表',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (_isLoading) ...<Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: const LinearProgressIndicator(minHeight: 6),
              ),
              const SizedBox(height: 14),
            ],
            ...page.items.map(
              (RankEntryData item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _RankCard(
                  item: item,
                  onTap: () => _navigateToHref(item.href),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return sections;
  }

  List<Widget> _buildDetailSections(DetailPageData page) {
    final Set<String> downloadedChapterKeys =
        _downloadedChapterPathKeysForDetail(page);
    final List<Widget> sections = <Widget>[
      _DetailHeroCard(
        page: page,
        onReadNow: page.startReadingHref.isNotEmpty
            ? () => _navigateToHref(page.startReadingHref)
            : null,
        onDownload: () => _showDetailDownloadPicker(page),
        onTagTap: _navigateToHref,
      ),
      const SizedBox(height: 18),
    ];

    if (page.summary.isNotEmpty) {
      sections.add(
        _SurfaceBlock(
          title: '內容簡介',
          child: Text(page.summary, style: const TextStyle(height: 1.7)),
        ),
      );
      sections.add(const SizedBox(height: 18));
    }

    final List<Widget> infoChips = <Widget>[
      if (page.authors.isNotEmpty) _InfoChip(label: '作者', value: page.authors),
      if (page.status.isNotEmpty) _InfoChip(label: '狀態', value: page.status),
      if (page.updatedAt.isNotEmpty)
        _InfoChip(label: '更新', value: page.updatedAt),
      if (page.heat.isNotEmpty) _InfoChip(label: '熱度', value: page.heat),
      if (page.aliases.isNotEmpty) _InfoChip(label: '別名', value: page.aliases),
    ];
    if (infoChips.isNotEmpty) {
      sections.add(
        _SurfaceBlock(
          title: '作品信息',
          child: Wrap(spacing: 10, runSpacing: 10, children: infoChips),
        ),
      );
      sections.add(const SizedBox(height: 18));
    }

    final List<Widget> chapterWidgets = <Widget>[];
    if (page.chapterGroups.isNotEmpty) {
      for (final ChapterGroupData group in page.chapterGroups) {
        chapterWidgets.add(
          Text(
            group.label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        );
        chapterWidgets.add(const SizedBox(height: 12));
        chapterWidgets.add(
          _ChapterGrid(
            chapters: group.chapters,
            onTap: _navigateToHref,
            downloadedChapterPathKeys: downloadedChapterKeys,
          ),
        );
        chapterWidgets.add(const SizedBox(height: 18));
      }
    } else if (page.chapters.isNotEmpty) {
      chapterWidgets.add(
        _ChapterGrid(
          chapters: page.chapters,
          onTap: _navigateToHref,
          downloadedChapterPathKeys: downloadedChapterKeys,
        ),
      );
    }

    sections.add(
      _SurfaceBlock(
        title: '章節目錄',
        actionLabel: page.chapters.isNotEmpty || page.chapterGroups.isNotEmpty
            ? '选择下载'
            : null,
        onActionTap: page.chapters.isNotEmpty || page.chapterGroups.isNotEmpty
            ? () => _showDetailDownloadPicker(page)
            : null,
        child: chapterWidgets.isEmpty
            ? const Text('章節還在整理中，向下刷新可重試。')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: chapterWidgets,
              ),
      ),
    );

    return sections;
  }

  List<Widget> _buildMessageSections(String message) {
    return <Widget>[
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          children: <Widget>[
            const Icon(Icons.layers_clear_rounded, size: 44),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.6),
            ),
            const SizedBox(height: 18),
            FilledButton(onPressed: _loadHome, child: const Text('回到首頁')),
          ],
        ),
      ),
    ];
  }

  Widget _buildReaderMode(BuildContext context, ReaderPageData page) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4EFE8),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _retryCurrentPage,
          child: ListView.builder(
            key: ValueKey<String>('reader-${page.uri}'),
            controller: _readerScrollController,
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            itemCount: page.imageUrls.length + 1,
            itemBuilder: (BuildContext context, int index) {
              if (index == page.imageUrls.length) {
                return Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: FilledButton.tonal(
                              onPressed: page.prevHref.isEmpty
                                  ? null
                                  : () => _navigateToHref(page.prevHref),
                              child: const Text('上一話'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: page.nextHref.isEmpty
                                  ? null
                                  : () => _navigateToHref(page.nextHref),
                              child: const Text('下一話'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: CachedNetworkImage(
                      imageUrl: page.imageUrls[index],
                      fit: BoxFit.fitWidth,
                      width: double.infinity,
                      cacheManager: EasyCopyImageCaches.readerCache,
                      progressIndicatorBuilder:
                          (
                            BuildContext context,
                            String url,
                            DownloadProgress progress,
                          ) {
                            return SizedBox(
                              height: 260,
                              child: Center(
                                child: CircularProgressIndicator(
                                  value: progress.progress,
                                ),
                              ),
                            );
                          },
                      errorWidget:
                          (BuildContext context, String url, Object error) {
                            return const SizedBox(
                              height: 220,
                              child: Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  size: 36,
                                ),
                              ),
                            );
                          },
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SurfaceBlock extends StatelessWidget {
  const _SurfaceBlock({
    required this.title,
    required this.child,
    this.actionLabel,
    this.onActionTap,
  });

  final String title;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onActionTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (actionLabel != null && onActionTap != null)
                  TextButton(onPressed: onActionTap, child: Text(actionLabel!)),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _HeroBannerCard extends StatelessWidget {
  const _HeroBannerCard({required this.banner, required this.onTap});

  final HeroBannerData banner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFF102038),
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            _NetworkImageBox(imageUrl: banner.imageUrl, aspectRatio: 1),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: <Color>[Color(0xCC0F1320), Color(0x330F1320)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  Text(
                    banner.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (banner.subtitle.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      banner.subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.84),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureBannerCard extends StatelessWidget {
  const _FeatureBannerCard({required this.banner, required this.onTap});

  final HeroBannerData banner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Ink(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFFFFEEE1), Color(0xFFFFD1B8)],
          ),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    '专题精选',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF995630),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    banner.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (banner.subtitle.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      banner.subtitle,
                      style: TextStyle(color: Colors.grey.shade800),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 14),
            SizedBox(
              width: 116,
              height: 116,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: _NetworkImageBox(
                  imageUrl: banner.imageUrl,
                  aspectRatio: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComicGrid extends StatelessWidget {
  const _ComicGrid({required this.items, required this.onTap});

  final List<ComicCardData> items;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text('暫時沒有可展示的內容。');
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 14,
        childAspectRatio: 0.50,
      ),
      itemBuilder: (BuildContext context, int index) {
        final ComicCardData item = items[index];
        return _ComicCard(item: item, onTap: () => onTap(item.href));
      },
    );
  }
}

class _ComicCard extends StatelessWidget {
  const _ComicCard({required this.item, required this.onTap});

  final ComicCardData item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double coverHeight = constraints.maxHeight * 0.64;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                height: coverHeight,
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: _NetworkImageBox(
                        imageUrl: item.coverUrl,
                        aspectRatio: 0.72,
                      ),
                    ),
                    if (item.badge.isNotEmpty)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF7B54),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            item.badge,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (item.subtitle.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    if (item.secondaryText.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 3),
                      Text(
                        item.secondaryText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FilterGroup extends StatelessWidget {
  const _FilterGroup({
    required this.group,
    required this.onTap,
    this.actionLabel,
    this.onActionTap,
  });

  final FilterGroupData group;
  final ValueChanged<String> onTap;
  final String? actionLabel;
  final VoidCallback? onActionTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  group.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (actionLabel != null && onActionTap != null)
                TextButton(
                  onPressed: onActionTap,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF0E8B84),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(actionLabel!),
                ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: group.options
              .map(
                (LinkAction option) => _LinkChip(
                  label: option.label,
                  active: option.active,
                  onTap: () => onTap(option.href),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _RankFilterGroup extends StatelessWidget {
  const _RankFilterGroup({
    required this.label,
    required this.helperText,
    required this.icon,
    required this.items,
    required this.onTap,
  });

  final String label;
  final String helperText;
  final IconData icon;
  final List<LinkAction> items;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final Widget chips = SizedBox(
      width: double.infinity,
      child: Wrap(
        alignment: WrapAlignment.start,
        spacing: 8,
        runSpacing: 8,
        children: items
            .map(
              (LinkAction item) => _LinkChip(
                label: item.label,
                active: item.active,
                onTap: () => onTap(item.href),
              ),
            )
            .toList(growable: false),
      ),
    );

    Widget buildLabelCard() {
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E7EE)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, size: 18, color: const Color(0xFF0E8B84)),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
            ),
            if (helperText.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                helperText,
                style: const TextStyle(
                  color: Color(0xFF6B7280),
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
            ],
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              buildLabelCard(),
              const SizedBox(height: 12),
              chips,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(width: 110, child: buildLabelCard()),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: chips,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LinkChip extends StatelessWidget {
  const _LinkChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor = active
        ? const Color(0x660E8B84)
        : const Color(0xFFF7F8FA);
    final Color borderColor = active
        ? const Color(0xCC0E8B84)
        : const Color(0xFFE2E6EB);
    final Color textColor = active
        ? const Color(0xFF17312E)
        : const Color(0xFF313742);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(999),
          boxShadow: active
              ? const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x330E8B84),
                    blurRadius: 12,
                    offset: Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: textColor,
            fontWeight: active ? FontWeight.w800 : FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _PagerCard extends StatelessWidget {
  const _PagerCard({
    required this.pager,
    required this.onPrev,
    required this.onNext,
  });

  final PagerData pager;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: FilledButton.tonal(
              onPressed: onPrev,
              child: const Text('上一页'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              children: <Widget>[
                Text(
                  pager.currentLabel.isEmpty ? '--' : pager.currentLabel,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (pager.totalLabel.isNotEmpty)
                  Text(
                    pager.totalLabel,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
              ],
            ),
          ),
          Expanded(
            child: FilledButton(onPressed: onNext, child: const Text('下一页')),
          ),
        ],
      ),
    );
  }
}

class _RankCard extends StatelessWidget {
  const _RankCard({required this.item, required this.onTap});

  final RankEntryData item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final IconData trendIcon;
    final Color trendColor;
    switch (item.trend) {
      case 'up':
        trendIcon = Icons.trending_up_rounded;
        trendColor = const Color(0xFF18A558);
      case 'down':
        trendIcon = Icons.trending_down_rounded;
        trendColor = const Color(0xFFD64545);
      default:
        trendIcon = Icons.trending_flat_rounded;
        trendColor = const Color(0xFF7A8494);
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F8FA),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFFF7B54),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                item.rankLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 86,
              height: 112,
              child: _NetworkImageBox(
                imageUrl: item.coverUrl,
                aspectRatio: 0.72,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.2,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (item.authors.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      item.authors,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          item.heat,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey.shade800,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: trendColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(trendIcon, size: 16, color: trendColor),
                            const SizedBox(width: 4),
                            Text(
                              item.trend,
                              style: TextStyle(
                                color: trendColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailHeroCard extends StatelessWidget {
  const _DetailHeroCard({
    required this.page,
    required this.onReadNow,
    required this.onDownload,
    required this.onTagTap,
  });

  final DetailPageData page;
  final VoidCallback? onReadNow;
  final VoidCallback? onDownload;
  final ValueChanged<String> onTagTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 122,
                child: _NetworkImageBox(
                  imageUrl: page.coverUrl,
                  aspectRatio: 0.72,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      page.title,
                      style: const TextStyle(
                        fontSize: 24,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (page.authors.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 10),
                      Text(
                        page.authors,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: page.tags
                          .take(6)
                          .map(
                            (LinkAction tag) => _LinkChip(
                              label: tag.label,
                              active: false,
                              onTap: () => onTagTap(tag.href),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: onReadNow,
                  icon: const Icon(Icons.chrome_reader_mode_rounded),
                  label: const Text('开始阅读'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: onDownload,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('缓存章节'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 132),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F6F8),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _ChapterGrid extends StatelessWidget {
  const _ChapterGrid({
    required this.chapters,
    required this.onTap,
    this.downloadedChapterPathKeys = const <String>{},
  });

  final List<ChapterData> chapters;
  final ValueChanged<String> onTap;
  final Set<String> downloadedChapterPathKeys;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: chapters.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 2.6,
      ),
      itemBuilder: (BuildContext context, int index) {
        final ChapterData chapter = chapters[index];
        final String chapterPathKey = Uri.tryParse(chapter.href) == null
            ? ''
            : Uri(path: Uri.parse(chapter.href).path).toString();
        final bool isDownloaded = downloadedChapterPathKeys.contains(
          chapterPathKey,
        );
        return InkWell(
          onTap: () => onTap(chapter.href),
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDownloaded
                  ? const Color(0xFFE9F7EF)
                  : const Color(0xFFF5F6F8),
              borderRadius: BorderRadius.circular(18),
              border: isDownloaded
                  ? Border.all(color: const Color(0xFF18A558))
                  : null,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    chapter.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (isDownloaded) ...<Widget>[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 18,
                    color: Color(0xFF18A558),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CachedComicCard extends StatelessWidget {
  const _CachedComicCard({
    required this.item,
    required this.onTap,
    this.onDelete,
  });

  final CachedComicLibraryEntry item;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  item.coverUrl.isEmpty
                      ? const _PlaceholderImage()
                      : CachedNetworkImage(
                          imageUrl: item.coverUrl,
                          fit: BoxFit.cover,
                          cacheManager: EasyCopyImageCaches.coverCache,
                          errorWidget:
                              (BuildContext context, String url, Object error) {
                                return const _PlaceholderImage();
                              },
                        ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xCC111111),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${item.cachedChapterCount}话',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (onDelete != null) ...<Widget>[
                          const SizedBox(width: 6),
                          Material(
                            color: const Color(0xCC111111),
                            borderRadius: BorderRadius.circular(999),
                            child: InkWell(
                              onTap: onDelete,
                              borderRadius: BorderRadius.circular(999),
                              child: const Padding(
                                padding: EdgeInsets.all(6),
                                child: Icon(
                                  Icons.delete_outline_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.comicTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          if (item.chapters.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              '最近缓存：${item.chapters.first.chapterTitle}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChapterPickerSection {
  const _ChapterPickerSection({required this.label, required this.chapters});

  final String label;
  final List<ChapterData> chapters;
}

class _PendingPageLoad {
  _PendingPageLoad({
    required this.requestedUri,
    required this.queryKey,
    required this.intent,
    required this.loadId,
    required this.targetTabIndex,
    required this.completer,
  });

  final Uri requestedUri;
  final PageQueryKey queryKey;
  final NavigationIntent intent;
  final int loadId;
  final int targetTabIndex;
  final Completer<EasyCopyPage> completer;
}

class _NetworkImageBox extends StatelessWidget {
  const _NetworkImageBox({required this.imageUrl, required this.aspectRatio});

  final String imageUrl;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: imageUrl.isEmpty
            ? const _PlaceholderImage()
            : CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                cacheManager: EasyCopyImageCaches.coverCache,
                errorWidget: (BuildContext context, String url, Object error) {
                  return const _PlaceholderImage();
                },
              ),
      ),
    );
  }
}

class _PlaceholderImage extends StatelessWidget {
  const _PlaceholderImage();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFFE4E7ED), Color(0xFFD3D9E4)],
        ),
      ),
      child: Center(
        child: Icon(Icons.image_outlined, size: 28, color: Color(0xFF5B6577)),
      ),
    );
  }
}
