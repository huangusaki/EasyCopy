part of '../app_screen.dart';

extension _AppScreenBootstrapActions on _AppScreenState {
  void _handlePreferencesChanged() {
    final DownloadPreferences previousDownloadPreferences =
        _shell.lastDownloadPrefs ?? _preferencesController.downloadPreferences;
    final DownloadPreferences nextDownloadPreferences =
        _preferencesController.downloadPreferences;
    _shell.lastDownloadPrefs = nextDownloadPreferences;

    if (!mounted) {
      return;
    }

    _setStateIfMounted(() {});

    final bool downloadPreferencesChanged = !previousDownloadPreferences
        .hasSameStorageLocation(nextDownloadPreferences);
    if (downloadPreferencesChanged) {
      unawaited(_refreshDownloadStorageState());
      if (_storageMigrationProgress.value == null) {
        unawaited(
          _refreshCachedComics(
            reason: CacheLibraryRefreshReason.preferencesChanged,
          ),
        );
      }
    }
  }

  Future<void> _bootstrap() async {
    final Stopwatch stopwatch = Stopwatch()..start();
    await Future.wait(<Future<void>>[
      _services.hostManager.ensureInitialized(),
      _services.session.ensureInitialized(),
      _preferencesController.ensureInitialized(),
      _services.readerProgressStore.ensureInitialized(),
      _services.localLibraryStore.ensureInitialized(),
      _services.searchHistoryStore.ensureInitialized(),
      PageCacheStore.instance.ensureInitialized(),
    ]);
    await _services.session.switchSite(_services.hostManager.currentSiteKey);
    _searchActions.replaceHistory(_services.searchHistoryStore.items);
    DebugTrace.log('bootstrap.initialized', <String, Object?>{
      'bootId': _shell.bootId,
      'elapsedMs': stopwatch.elapsedMilliseconds,
    });
    Uri? debugUri;
    if (kDebugMode && AppConfig.debugStartUri.trim().isNotEmpty) {
      debugUri = Uri.tryParse(AppConfig.debugStartUri.trim());
      if (debugUri != null) {
        DebugTrace.log('bootstrap.debug_start_uri', <String, Object?>{
          'bootId': _shell.bootId,
          'uri': debugUri.toString(),
        });
      }
    }
    final int initialTabIndex = _preferencesController.lastPrimaryTabIndex
        .clamp(0, appDestinations.length - 1)
        .toInt();
    final Uri homeUri = debugUri ?? appDestinations[initialTabIndex].uri;
    if (!mounted) {
      return;
    }
    _setStateIfMounted(() {
      _setSelectedPrimaryTabIndex(tabIndexForUri(homeUri), persist: false);
    });
    _searchActions.syncFromCurrentUri();
    await _loadUri(homeUri, historyMode: NavigationIntent.resetToRoot);
    DebugTrace.log('bootstrap.home_ready', <String, Object?>{
      'bootId': _shell.bootId,
      'elapsedMs': stopwatch.elapsedMilliseconds,
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runDeferredBootstrapTasks());
    });
  }

  Future<void> _runDeferredBootstrapTasks() async {
    await Future.wait(<Future<void>>[
      _refreshHostsAfterBootstrap(),
      _prepareDownloadBootstrap(),
    ]);
    await _downloadQueueManager.recoverStorageMigration();
    if (!_downloadQueueManager.shouldBypassCachedReaderLookup) {
      await _refreshCachedComics(reason: CacheLibraryRefreshReason.bootstrap);
    } else {
      DebugTrace.log('cached_library.refresh_deferred', <String, Object?>{
        'bootId': _shell.bootId,
        'reason': CacheLibraryRefreshReason.bootstrap.name,
        'deferReason': 'storage_migration_active',
      });
    }
    await _ensureDownloadQueueRunning();
    unawaited(_prefetchPrimaryTabRoots());
  }

  /// 后台预热「发现 / 排行」根页。
  Future<void> _prefetchPrimaryTabRoots() async {
    await Future<void>.delayed(const Duration(seconds: 4));
    for (final int tabIndex in <int>[1, 2]) {
      if (!mounted || _isReaderMode) {
        return;
      }
      if (_standardPageLoadController.pendingLoad != null) {
        return;
      }
      final Uri rootUri = AppConfig.rewriteToCurrentHost(
        appDestinations[tabIndex].uri,
      );
      final PageQueryKey key = _pageQueryKeyForUri(rootUri);
      try {
        final CachedPageHit? cached = await _pageRepository.readCached(key);
        if (cached != null && !cached.envelope.isSoftExpired(DateTime.now())) {
          continue;
        }
        if (!mounted ||
            _isReaderMode ||
            _standardPageLoadController.pendingLoad != null) {
          return;
        }
        DebugTrace.log('prefetch.tab_root', <String, Object?>{
          'bootId': _shell.bootId,
          'uri': rootUri.toString(),
        });
        await _pageRepository.loadFresh(rootUri, authScope: key.authScope);
      } catch (_) {
        // 预取失败走前台错误路径。
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }
}
