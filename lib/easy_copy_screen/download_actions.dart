part of '../easy_copy_screen.dart';

extension _EasyCopyScreenDownloadActions on _EasyCopyScreenState {
  Future<void> _prepareDeferredDownloadBootstrapState() {
    return Future.wait(<Future<void>>[
      _refreshDownloadStorageState(),
      _restoreDownloadQueue(),
    ]);
  }

  Future<void> _refreshCachedComics({
    CacheLibraryRefreshReason reason = CacheLibraryRefreshReason.manual,
    bool forceRescan = false,
  }) {
    final Future<void>? activeTask = _cachedLibraryRefreshTask;
    if (activeTask != null) {
      _queuedCachedLibraryRefreshReason = reason;
      _queuedCachedLibraryForceRescan =
          _queuedCachedLibraryForceRescan || forceRescan;
      return activeTask;
    }
    late final Future<void> task;
    task = _runCachedLibraryRefreshLoop(reason, forceRescan: forceRescan)
        .whenComplete(() {
          if (identical(_cachedLibraryRefreshTask, task)) {
            _cachedLibraryRefreshTask = null;
          }
        });
    _cachedLibraryRefreshTask = task;
    return task;
  }

  Future<void> _runCachedLibraryRefreshLoop(
    CacheLibraryRefreshReason initialReason, {
    required bool forceRescan,
  }) async {
    CacheLibraryRefreshReason currentReason = initialReason;
    bool currentForceRescan = forceRescan;
    while (true) {
      _queuedCachedLibraryRefreshReason = null;
      _queuedCachedLibraryForceRescan = false;
      final Stopwatch stopwatch = Stopwatch()..start();
      DebugTrace.log('cached_library.refresh_start', <String, Object?>{
        'bootId': _bootId,
        'reason': currentReason.name,
        'forceRescan': currentForceRescan,
      });
      final List<CachedComicLibraryEntry> comics = await _downloadService
          .loadCachedLibrary(forceRescan: currentForceRescan);
      if (!mounted) {
        _cachedComics = comics;
      } else {
        _setStateIfMounted(() {
          _cachedComics = comics;
        });
      }
      DebugTrace.log('cached_library.refresh_complete', <String, Object?>{
        'bootId': _bootId,
        'reason': currentReason.name,
        'forceRescan': currentForceRescan,
        'comicCount': comics.length,
        'elapsedMs': stopwatch.elapsedMilliseconds,
      });
      final CacheLibraryRefreshReason? queuedReason =
          _queuedCachedLibraryRefreshReason;
      final bool queuedForceRescan = _queuedCachedLibraryForceRescan;
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
    final int comicCount = _cachedComics.length;
    final int chapterCount = _cachedComics.fold(
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
    _showSnackBar(message);
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
    _updateCachedComicSnapshotInMemory(page, snapshot);
    try {
      await _downloadService.upsertCachedComicDetailSnapshot(page);
    } catch (_) {
      return;
    }
  }

  void _updateCachedComicSnapshotInMemory(
    DetailPageData page,
    CachedComicDetailSnapshot snapshot,
  ) {
    final String targetComicKey = _comicQueueKey(page.uri);
    final int index = _cachedComics.indexWhere((CachedComicLibraryEntry entry) {
      if (targetComicKey.isNotEmpty &&
          _comicQueueKey(entry.comicHref) == targetComicKey) {
        return true;
      }
      return entry.comicTitle == page.title;
    });
    if (index == -1) {
      return;
    }

    final CachedComicLibraryEntry current = _cachedComics[index];
    final CachedComicLibraryEntry next = current.copyWith(
      comicTitle: page.title.isEmpty ? current.comicTitle : page.title,
      comicHref: page.uri.isEmpty ? current.comicHref : page.uri,
      coverUrl: page.coverUrl.isEmpty ? current.coverUrl : page.coverUrl,
      detailSnapshot: snapshot,
    );
    if (mounted) {
      _setStateIfMounted(() {
        _cachedComics = <CachedComicLibraryEntry>[
          ..._cachedComics.take(index),
          next,
          ..._cachedComics.skip(index + 1),
        ];
      });
      return;
    }
    _cachedComics = <CachedComicLibraryEntry>[
      ..._cachedComics.take(index),
      next,
      ..._cachedComics.skip(index + 1),
    ];
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
      detailSnapshot: page.toCachedDetailSnapshot(),
    );
  }

  Future<void> _enqueueSelectedChapters(
    DetailPageData page,
    List<ChapterData> chapters,
  ) async {
    final DownloadQueueSnapshot snapshot = _downloadQueueSnapshot;
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
    final List<DownloadQueueTask> newTasks = <DownloadQueueTask>[];

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
      _showSnackBar(enqueueResult.failureNotice());
      return;
    }

    final bool keepPaused = await _downloadQueueManager.addTasks(newTasks);
    _showSnackBar(enqueueResult.successNotice(keepPaused: keepPaused));
  }

  Future<void> _pauseDownloadQueue() async {
    final DownloadQueueSnapshot snapshot = _downloadQueueSnapshot;
    if (snapshot.isEmpty || snapshot.isPaused) {
      return;
    }
    await _downloadQueueManager.pauseQueue();
    _showSnackBar('后台缓存将在当前图片完成后暂停');
  }

  Future<void> _resumeDownloadQueue() async {
    if (_downloadQueueSnapshot.isEmpty) {
      return;
    }
    await _downloadQueueManager.resumeQueue();
    _showSnackBar('已继续后台缓存');
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

    await _downloadQueueManager.removeQueuedComic(task);
    _showSnackBar('已移出 ${task.comicTitle} 的缓存任务');
  }

  Future<void> _confirmRemoveQueuedComicAndCache(DownloadQueueTask task) async {
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
    _showSnackBar('已移除 ${task.comicTitle} 的下载任务和本地缓存');
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
    _showSnackBar('已清空下载队列');
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
    _showSnackBar('已移出 ${task.chapterLabel}');
  }

  Future<void> _retryDownloadQueueTask(DownloadQueueTask task) async {
    await _downloadQueueManager.retryTask(task);
    _showSnackBar('已重新加入 ${task.chapterLabel}');
  }

  bool _canEditDownloadStorage() {
    final String? reason = _downloadQueueManager.storageEditBlockReason();
    if (reason != null) {
      _showSnackBar(reason);
      return false;
    }
    return true;
  }

  Future<void> _pickDownloadStorageDirectory() async {
    if (!_downloadQueueManager.supportsCustomStorageSelection ||
        !_canEditDownloadStorage()) {
      return;
    }
    final PickedDocumentTreeDirectory? pickedDirectory =
        await _downloadStorageService.pickDocumentTreeDirectory();
    if (pickedDirectory != null) {
      final DownloadPreferences nextPreferences = DownloadPreferences(
        mode: DownloadStorageMode.customDirectory,
        customBasePath: '',
        customTreeUri: pickedDirectory.treeUri,
        customDisplayPath: pickedDirectory.displayName,
        usePickedDirectoryAsRoot: true,
      );
      await _applyDownloadStoragePreferences(
        nextPreferences,
        successMessage: '已开始迁移到新的存储位置',
      );
    }
  }

  Future<void> _resetDownloadStorageDirectory() async {
    if (!_canEditDownloadStorage()) {
      return;
    }
    await _applyDownloadStoragePreferences(
      const DownloadPreferences(),
      successMessage: '已开始迁移到默认缓存目录',
    );
  }

  Future<void> _applyDownloadStoragePreferences(
    DownloadPreferences nextPreferences, {
    required String successMessage,
  }) async {
    try {
      final DownloadStorageMigrationResult? result = await _downloadQueueManager
          .applyStoragePreferences(nextPreferences);
      if (result == null) {
        return;
      }
      _showSnackBar('$successMessage，完成后自动切换');
    } catch (error) {
      await _refreshDownloadStorageState();
      _showSnackBar(_formatDownloadError(error));
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
