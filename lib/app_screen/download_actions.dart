part of '../app_screen.dart';

extension _AppScreenDownloadActions on _AppScreenState {
  Future<void> _prepareDownloadBootstrap() {
    return Future.wait(<Future<void>>[
      _refreshDownloadStorageState(),
      _restoreDownloadQueue(),
    ]);
  }

  Set<String> _downloadedChapterKeys(DetailPageData page) {
    return downloadedChapterKeysForDetail(
      page,
      cachedComics: _library.cachedComics,
      chapterPathKey: _chapterKeys.pathKey,
    );
  }

  Future<void> _showDetailDownloadPicker(DetailPageData page) async {
    final List<ChapterData>? selectedChapters =
        await showDetailChapterDownloadPicker(
          context: context,
          page: page,
          downloadedKeys: _downloadedChapterKeys(page),
          chapterPathKey: _chapterKeys.pathKey,
        );
    if (selectedChapters == null || selectedChapters.isEmpty || !mounted) {
      return;
    }
    await _enqueueSelectedChapters(page, selectedChapters);
  }

  Future<void> _refreshCachedComics({
    CacheLibraryRefreshReason reason = CacheLibraryRefreshReason.manual,
    bool forceRescan = false,
  }) {
    final Future<void>? activeTask = _library.refreshTask;
    if (activeTask != null) {
      _library.pendingRefresh = reason;
      _library.queuedForceRescan = _library.queuedForceRescan || forceRescan;
      return activeTask;
    }
    late final Future<void> task;
    task = _runCachedLibraryRefreshLoop(reason, forceRescan: forceRescan)
        .whenComplete(() {
          if (identical(_library.refreshTask, task)) {
            _library.refreshTask = null;
          }
        });
    _library.refreshTask = task;
    return task;
  }

  Future<void> _runCachedLibraryRefreshLoop(
    CacheLibraryRefreshReason initialReason, {
    required bool forceRescan,
  }) async {
    CacheLibraryRefreshReason currentReason = initialReason;
    bool currentForceRescan = forceRescan;
    while (true) {
      _library.pendingRefresh = null;
      _library.queuedForceRescan = false;
      final Stopwatch stopwatch = Stopwatch()..start();
      DebugTrace.log('cached_library.refresh_start', <String, Object?>{
        'bootId': _shell.bootId,
        'reason': currentReason.name,
        'forceRescan': currentForceRescan,
      });
      final List<CachedComicLibraryEntry> comics = await _services
          .downloadService
          .loadCachedLibrary(forceRescan: currentForceRescan);
      if (!mounted) {
        _library.cachedComics = comics;
      } else {
        _setStateIfMounted(() {
          _library.cachedComics = comics;
        });
      }
      DebugTrace.log('cached_library.refresh_complete', <String, Object?>{
        'bootId': _shell.bootId,
        'reason': currentReason.name,
        'forceRescan': currentForceRescan,
        'comicCount': comics.length,
        'elapsedMs': stopwatch.elapsedMilliseconds,
      });
      final CacheLibraryRefreshReason? queuedReason = _library.pendingRefresh;
      final bool queuedForceRescan = _library.queuedForceRescan;
      if (queuedReason == null && !queuedForceRescan) {
        break;
      }
      currentReason = queuedReason ?? currentReason;
      currentForceRescan = queuedForceRescan;
    }
  }

  Future<String> _rescanCurrentDownloadStorage() async {
    await _refreshCachedComics(
      reason: CacheLibraryRefreshReason.storageRescan,
      forceRescan: true,
    );
    if (!mounted) {
      return '';
    }
    final int comicCount = _library.cachedComics.length;
    final int chapterCount = _library.cachedComics.fold(
      0,
      (int total, CachedComicLibraryEntry entry) =>
          total + entry.cachedChapterCount,
    );
    return comicCount == 0
        ? '当前目录未发现可恢复缓存'
        : '已恢复 $comicCount 部漫画，$chapterCount 话缓存';
  }

  Future<void> _refreshDownloadStorageState({
    DownloadPreferences? preferences,
  }) async {
    await _downloadQueueManager.refreshStorageState(preferences: preferences);
  }

  void _handleDownloadQueueNotice(String message) {
    if (!mounted || message.trim().isEmpty) {
      return;
    }
    _showNotice(message);
  }

  DownloadQueueSnapshot get _downloadQueueSnapshot =>
      _downloadQueueSnapshotNotifier.value;

  Future<void> _restoreDownloadQueue() async {
    await _downloadQueueManager.restoreQueue();
  }

  String _comicQueueKey(String value) {
    final Uri? uri = Uri.tryParse(value);
    if (uri == null) {
      return value.trim();
    }
    return Uri(path: AppConfig.rewriteToCurrentHost(uri).path).toString();
  }

  Future<void> _persistCachedDetailSnapshot(DetailPageData page) async {
    final CachedComicDetailSnapshot snapshot = page.toCachedDetailSnapshot();
    if (snapshot.isEmpty) {
      return;
    }
    _updateCachedComicSnapshot(page, snapshot);
    try {
      await _services.downloadService.upsertCachedComicDetailSnapshot(page);
    } catch (_) {
      return;
    }
  }

  void _updateCachedComicSnapshot(
    DetailPageData page,
    CachedComicDetailSnapshot snapshot,
  ) {
    final String targetComicKey = _comicQueueKey(page.uri);
    final int index = _library.cachedComics.indexWhere((
      CachedComicLibraryEntry entry,
    ) {
      if (targetComicKey.isNotEmpty &&
          _comicQueueKey(entry.comicHref) == targetComicKey) {
        return true;
      }
      return entry.comicTitle == page.title;
    });
    if (index == -1) {
      return;
    }

    final CachedComicLibraryEntry current = _library.cachedComics[index];
    final CachedComicLibraryEntry next = current.copyWith(
      comicTitle: page.title.isEmpty ? current.comicTitle : page.title,
      comicHref: page.uri.isEmpty ? current.comicHref : page.uri,
      coverUrl: page.coverUrl.isEmpty ? current.coverUrl : page.coverUrl,
      detailSnapshot: snapshot,
    );
    if (mounted) {
      _setStateIfMounted(() {
        _library.cachedComics = <CachedComicLibraryEntry>[
          ..._library.cachedComics.take(index),
          next,
          ..._library.cachedComics.skip(index + 1),
        ];
      });
      return;
    }
    _library.cachedComics = <CachedComicLibraryEntry>[
      ..._library.cachedComics.take(index),
      next,
      ..._library.cachedComics.skip(index + 1),
    ];
  }

  DownloadQueueTask _buildDownloadQueueTask(
    DetailPageData page,
    Uri chapterUri,
    ChapterData chapter,
  ) {
    final DateTime now = DateTime.now();
    final String comicKey = _comicQueueKey(page.uri);
    final String chapterKey = _chapterKeys.pathKey(chapterUri.toString());
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
      detailSnapshot: page.toCachedDetailSnapshot(),
    );
  }

  Future<void> _enqueueSelectedChapters(
    DetailPageData page,
    List<ChapterData> chapters,
  ) async {
    final DownloadQueueSnapshot snapshot = _downloadQueueSnapshot;
    final Set<String> downloadedKeys = _downloadedChapterKeys(page);
    final Set<String> queuedChapterKeys = snapshot.tasks
        .map((DownloadQueueTask task) => task.chapterKey)
        .toSet();
    final Uri detailUri = Uri.parse(page.uri);

    int addedCount = 0;
    int skippedCachedCount = 0;
    int skippedQueuedCount = 0;
    final List<DownloadQueueTask> newTasks = <DownloadQueueTask>[];

    for (final ChapterData chapter in chapters) {
      final Uri chapterUri = AppConfig.resolveNavigationUri(
        chapter.href,
        currentUri: detailUri,
      );
      final String chapterKey = _chapterKeys.pathKey(chapterUri.toString());
      if (downloadedKeys.contains(chapterKey)) {
        skippedCachedCount += 1;
        continue;
      }
      if (queuedChapterKeys.contains(chapterKey)) {
        skippedQueuedCount += 1;
        continue;
      }

      newTasks.add(_buildDownloadQueueTask(page, chapterUri, chapter));
      queuedChapterKeys.add(chapterKey);
      addedCount += 1;
    }

    final DownloadChapterEnqueueResult enqueueResult =
        DownloadChapterEnqueueResult(
          addedCount: addedCount,
          skippedCachedCount: skippedCachedCount,
          skippedQueuedCount: skippedQueuedCount,
        );

    if (!enqueueResult.hasAddedTasks) {
      _showNotice(enqueueResult.failureNotice());
      return;
    }

    final bool keepPaused = await _downloadQueueManager.addTasks(newTasks);
    _showNotice(enqueueResult.successNotice(keepPaused: keepPaused));
  }

  Future<void> _pauseDownloadQueue() async {
    final DownloadQueueSnapshot snapshot = _downloadQueueSnapshot;
    if (snapshot.isEmpty || snapshot.isPaused) {
      return;
    }
    await _downloadQueueManager.pauseQueue();
    _showNotice('后台缓存将在当前图片完成后暂停');
  }

  Future<void> _resumeDownloadQueue() async {
    if (_downloadQueueSnapshot.isEmpty) {
      return;
    }
    await _downloadQueueManager.resumeQueue();
    _showNotice('已继续后台缓存');
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
    await _downloadQueueManager.deleteCachedComic(item, comicKey: comicKey);
    _showNotice('已删除 ${item.comicTitle} 的缓存');
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

    await _downloadQueueManager.removeQueuedComic(task);
    _showNotice('已移出 ${task.comicTitle} 的缓存任务');
  }

  Future<void> _confirmRemoveComicCache(DownloadQueueTask task) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('移除漫画缓存'),
          content: Text('确认停止《${task.comicTitle}》的后台缓存，并删除这部漫画已缓存的章节吗？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('移除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }

    await _downloadQueueManager.removeComicAndDeleteCache(task);
    _showNotice('已移除 ${task.comicTitle} 的下载任务和本地缓存');
  }

  Future<void> _confirmClearDownloadQueue() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('移除全部下载任务'),
          content: const Text('确认清空当前下载队列，并清理未完成文件吗？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('清空'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }

    await _downloadQueueManager.clearQueue();
    _showNotice('已清空下载队列');
  }

  Future<void> _confirmRemoveQueuedTask(DownloadQueueTask task) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('移出章节任务'),
          content: Text('确认移出《${task.comicTitle}》的 ${task.chapterLabel} 吗？'),
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

    await _downloadQueueManager.removeQueuedTask(task);
    _showNotice('已移出 ${task.chapterLabel}');
  }

  Future<void> _retryDownloadQueueTask(DownloadQueueTask task) async {
    await _downloadQueueManager.retryTask(task);
    _showNotice('已重新加入 ${task.chapterLabel}');
  }

  bool _canEditDownloadStorage() {
    final String? reason = _downloadQueueManager.storageEditBlockReason();
    if (reason != null) {
      _showNotice(reason);
      return false;
    }
    return true;
  }

  Future<void> _pickDownloadStorageDirectory() async {
    if (!_downloadQueueManager.supportsCustomStorageSelection ||
        !_canEditDownloadStorage()) {
      return;
    }
    if (PlatformCapabilities.isWindows) {
      final DownloadStorageState currentState =
          _downloadStorageStateNotifier.value;
      final String? selectedPath = await getDirectoryPath(
        initialDirectory: currentState.displayPath.trim().isEmpty
            ? null
            : currentState.displayPath,
        confirmButtonText: '选择',
        canCreateDirectories: true,
      );
      final String normalizedPath = (selectedPath ?? '').trim();
      if (normalizedPath.isEmpty) {
        return;
      }
      final DownloadPreferences nextPreferences = DownloadPreferences(
        mode: DownloadStorageMode.customDirectory,
        customBasePath: normalizedPath,
        customTreeUri: '',
        customDisplayPath: normalizedPath,
        usePickedDirectoryAsRoot: true,
      );
      await _applyStoragePrefs(nextPreferences, successMessage: '已开始迁移到新的存储位置');
      return;
    }
    final PickedDocumentTreeDirectory? pickedDirectory = await _services
        .downloadStorageService
        .pickDocumentTreeDirectory();
    if (pickedDirectory != null) {
      final DownloadPreferences nextPreferences = DownloadPreferences(
        mode: DownloadStorageMode.customDirectory,
        customBasePath: '',
        customTreeUri: pickedDirectory.treeUri,
        customDisplayPath: pickedDirectory.displayName,
        usePickedDirectoryAsRoot: true,
      );
      await _applyStoragePrefs(nextPreferences, successMessage: '已开始迁移到新的存储位置');
    }
  }

  Future<void> _resetDownloadStorageDirectory() async {
    if (!_canEditDownloadStorage()) {
      return;
    }
    await _applyStoragePrefs(
      const DownloadPreferences(),
      successMessage: '已开始迁移到默认缓存目录',
    );
  }

  Future<void> _applyStoragePrefs(
    DownloadPreferences nextPreferences, {
    required String successMessage,
  }) async {
    try {
      final DownloadStorageMigrationResult? result = await _downloadQueueManager
          .applyStoragePreferences(nextPreferences);
      if (result == null) {
        return;
      }
      _showNotice('$successMessage，完成后自动切换');
    } catch (error) {
      await _refreshDownloadStorageState();
      _showNotice(_formatDownloadError(error));
    }
  }

  Future<void> _ensureDownloadQueueRunning() async {
    await _downloadQueueManager.ensureRunning();
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
}
