part of '../easy_copy_screen.dart';

extension _EasyCopyScreenBootstrapActions on _EasyCopyScreenState {
  void _handlePreferencesChanged() {
    final DownloadPreferences previousDownloadPreferences =
        _lastObservedDownloadPreferences ??
        _preferencesController.downloadPreferences;
    final DownloadPreferences nextDownloadPreferences =
        _preferencesController.downloadPreferences;
    _lastObservedDownloadPreferences = nextDownloadPreferences;

    if (!mounted) {
      return;
    }

    _setStateIfMounted(() {});

    final bool downloadPreferencesChanged = !previousDownloadPreferences
        .hasSameStorageLocation(nextDownloadPreferences);
    if (downloadPreferencesChanged) {
      unawaited(_refreshDownloadStorageState());
      if (_downloadStorageMigrationProgressNotifier.value == null) {
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
      _hostManager.ensureInitialized(),
      _session.ensureInitialized(),
      _preferencesController.ensureInitialized(),
      _readerProgressStore.ensureInitialized(),
      _localLibraryStore.ensureInitialized(),
      _searchHistoryStore.ensureInitialized(),
      PageCacheStore.instance.ensureInitialized(),
    ]);
    _searchHistoryEntries = _searchHistoryStore.items;
    DebugTrace.log('bootstrap.initialized', <String, Object?>{
      'bootId': _bootId,
      'elapsedMs': stopwatch.elapsedMilliseconds,
    });
    Uri? debugUri;
    if (kDebugMode && AppConfig.debugStartUri.trim().isNotEmpty) {
      debugUri = Uri.tryParse(AppConfig.debugStartUri.trim());
      if (debugUri != null) {
        DebugTrace.log('bootstrap.debug_start_uri', <String, Object?>{
          'bootId': _bootId,
          'uri': debugUri.toString(),
        });
      }
    }
    final Uri homeUri = debugUri ?? appDestinations.first.uri;
    if (!mounted) {
      return;
    }
    _setStateIfMounted(() {
      _selectedIndex = tabIndexForUri(homeUri);
    });
    _syncSearchController();
    await _loadUri(homeUri, historyMode: NavigationIntent.resetToRoot);
    DebugTrace.log('bootstrap.home_ready', <String, Object?>{
      'bootId': _bootId,
      'elapsedMs': stopwatch.elapsedMilliseconds,
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runDeferredBootstrapTasks());
    });
  }

  Future<void> _runDeferredBootstrapTasks() async {
    await Future.wait(<Future<void>>[
      _refreshHostsInBackgroundAfterBootstrap(),
      _prepareDeferredDownloadBootstrapState(),
    ]);
    await _downloadQueueManager.recoverInterruptedStorageMigration();
    if (!_downloadQueueManager.shouldBypassCachedReaderLookup) {
      await _refreshCachedComics(reason: CacheLibraryRefreshReason.bootstrap);
    } else {
      DebugTrace.log('cached_library.refresh_deferred', <String, Object?>{
        'bootId': _bootId,
        'reason': CacheLibraryRefreshReason.bootstrap.name,
        'deferReason': 'storage_migration_active',
      });
    }
    await _ensureDownloadQueueRunning();
  }
}
