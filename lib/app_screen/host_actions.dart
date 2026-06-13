part of '../app_screen.dart';

extension _AppScreenHostActions on _AppScreenState {
  Future<void> _refreshHostsAfterBootstrap() {
    final Future<void>? activeTask = _shell.backgroundHostRefreshTask;
    if (activeTask != null) {
      return activeTask;
    }
    final Future<void> refreshTask = _runBootstrapHostRefresh();
    _shell.backgroundHostRefreshTask = refreshTask;
    return refreshTask.whenComplete(() {
      if (identical(_shell.backgroundHostRefreshTask, refreshTask)) {
        _shell.backgroundHostRefreshTask = null;
      }
    });
  }

  Future<void> _runBootstrapHostRefresh() async {
    final String previousHost = _services.hostManager.currentHost;
    final DateTime? previousCheckedAt =
        _services.hostManager.probeSnapshot?.checkedAt;
    DebugTrace.log('host.bootstrap_probe_start', <String, Object?>{
      'bootId': _shell.bootId,
      'currentHost': previousHost,
      'checkedAt': previousCheckedAt?.toIso8601String(),
    });
    try {
      await _services.hostManager.refreshProbes(force: true);
      final String nextHost = _services.hostManager.currentHost;
      final DateTime? nextCheckedAt =
          _services.hostManager.probeSnapshot?.checkedAt;
      final bool hostChanged = nextHost != previousHost;
      if (hostChanged) {
        await _syncHostCookies();
      }
      DebugTrace.log('host.bootstrap_probe_complete', <String, Object?>{
        'bootId': _shell.bootId,
        'previousHost': previousHost,
        'nextHost': nextHost,
        'hostChanged': hostChanged,
        'checkedAt': nextCheckedAt?.toIso8601String(),
      });
      if (!mounted || (!hostChanged && nextCheckedAt == previousCheckedAt)) {
        return;
      }
      _mutateSessionState(() {}, syncSearch: false);
    } catch (error) {
      DebugTrace.log('host.bootstrap_probe_failed', <String, Object?>{
        'bootId': _shell.bootId,
        'currentHost': previousHost,
        'checkedAt': previousCheckedAt?.toIso8601String(),
        'error': error.toString(),
      });
    }
  }

  Future<void> _loadAppVersionInfo() async {
    try {
      final PackageInfo packageInfo = await PackageInfo.fromPlatform();
      if (!mounted) {
        _shell.appVersion = packageInfo.version.trim();
        _shell.appBuildNumber = packageInfo.buildNumber.trim();
        return;
      }
      _setStateIfMounted(() {
        _shell.appVersion = packageInfo.version.trim();
        _shell.appBuildNumber = packageInfo.buildNumber.trim();
      });
    } catch (_) {
      // Keep placeholder values when package info is unavailable.
    }
  }

  Future<void> _checkForUpdates() async {
    if (_shell.isCheckingForUpdates) {
      return;
    }
    if (_shell.appVersion.isEmpty) {
      await _loadAppVersionInfo();
    }
    final String currentVersion = _shell.appVersion.trim();
    if (currentVersion.isEmpty) {
      _showNotice('版本信息不可用');
      return;
    }

    _mutateSessionState(() {
      _shell.isCheckingForUpdates = true;
    }, syncSearch: false);
    try {
      final AppUpdateInfo updateInfo = await AppUpdateChecker.instance
          .checkForUpdates(currentVersion: currentVersion);
      if (!mounted) {
        return;
      }
      if (!updateInfo.hasUpdate) {
        _showNotice('已是最新版本');
        return;
      }

      final bool? shouldOpenRelease = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('发现新版本'),
            content: Text(
              '${updateInfo.currentVersion} -> ${updateInfo.latestVersion}',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('前往'),
              ),
            ],
          );
        },
      );
      if (shouldOpenRelease == true) {
        await _launchExternalUri(updateInfo.releaseUri);
      }
    } catch (_) {
      if (mounted) {
        _showNotice('检查更新失败');
      }
    } finally {
      if (mounted) {
        _mutateSessionState(() {
          _shell.isCheckingForUpdates = false;
        }, syncSearch: false);
      } else {
        _shell.isCheckingForUpdates = false;
      }
    }
  }

  Future<void> _openProjectRepository() async {
    await _launchExternalUri(AppUpdateChecker.repositoryUri);
  }

  Future<void> _launchExternalUri(Uri uri) async {
    try {
      final bool launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        _showNotice('打开失败');
      }
    } catch (_) {
      if (mounted) {
        _showNotice('打开失败');
      }
    }
  }

  Future<void> _refreshHostSettings() async {
    if (_shell.isUpdatingHostSettings) {
      return;
    }
    _mutateSessionState(() {
      _shell.isUpdatingHostSettings = true;
    }, syncSearch: false);
    try {
      await _services.hostManager.refreshProbes(force: true);
      await _syncHostCookies();
      if (!mounted) {
        return;
      }
      final bool isPinned = _services.hostManager.sessionPinnedHost != null;
      _showNotice(
        isPinned
            ? '测速完成，当前仍手动锁定到域名 ${_services.hostManager.currentHost}'
            : '测速完成，已自动选择 ${_services.hostManager.currentHost}',
      );
    } catch (_) {
      if (mounted) {
        _showNotice('测速失败，请稍后重试');
      }
    } finally {
      if (mounted) {
        _mutateSessionState(() {
          _shell.isUpdatingHostSettings = false;
        }, syncSearch: false);
      } else {
        _shell.isUpdatingHostSettings = false;
      }
    }
  }

  Future<void> _selectHost(String host) async {
    final String normalizedHost = host.trim().toLowerCase();
    if (normalizedHost.isEmpty || _shell.isUpdatingHostSettings) {
      return;
    }
    _mutateSessionState(() {
      _shell.isUpdatingHostSettings = true;
    }, syncSearch: false);
    try {
      await _services.hostManager.pinSessionHost(normalizedHost);
      await _syncHostCookies();
      if (mounted) {
        _showNotice('已切换到 $normalizedHost');
      }
    } catch (error) {
      if (mounted) {
        final String message = error is StateError
            ? error.message.toString()
            : '切换域名失败，请稍后重试';
        _showNotice(message);
      }
    } finally {
      if (mounted) {
        _mutateSessionState(() {
          _shell.isUpdatingHostSettings = false;
        }, syncSearch: false);
      } else {
        _shell.isUpdatingHostSettings = false;
      }
    }
  }

  Future<void> _useAutomaticHostSelection() async {
    if (_shell.isUpdatingHostSettings) {
      return;
    }
    _mutateSessionState(() {
      _shell.isUpdatingHostSettings = true;
    }, syncSearch: false);
    try {
      await _services.hostManager.clearSessionPin();
      await _services.hostManager.refreshProbes(force: true);
      await _syncHostCookies();
      if (mounted) {
        _showNotice('已恢复自动选择，当前域名 ${_services.hostManager.currentHost}');
      }
    } catch (_) {
      if (mounted) {
        _showNotice('恢复自动选择失败，请稍后重试');
      }
    } finally {
      if (mounted) {
        _mutateSessionState(() {
          _shell.isUpdatingHostSettings = false;
        }, syncSearch: false);
      } else {
        _shell.isUpdatingHostSettings = false;
      }
    }
  }

  void _showNotice(String message) {
    if (!mounted) {
      return;
    }
    TopNotice.show(context, message, tone: TopNotice.toneForMessage(message));
  }

  Future<void> _handleMainFrameFailure(String message) async {
    _web.consecutiveFrameFailures += 1;
    if (!mounted) {
      return;
    }
    if (_pendingPageLoad != null) {
      _failPendingPageLoad(message);
    } else if (_page == null) {
      _mutateSessionState(() {
        _tabSessionStore.updateError(
          _nav.selectedIndex,
          _currentEntry.routeKey,
          message,
        );
      });
    } else {
      _mutateSessionState(() {
        _tabSessionStore.updateCurrent(
          _nav.selectedIndex,
          (PrimaryTabRouteEntry entry) =>
              entry.copyWith(isLoading: false, clearError: true),
        );
      });
      _showNotice(message);
    }
    if (_web.isFailingOver) {
      return;
    }
    if (await _tryRecoverHost(message)) {
      _web.consecutiveFrameFailures = 0;
      return;
    }
    if (_services.hostManager.sessionPinnedHost != null ||
        _web.consecutiveFrameFailures < 2) {
      return;
    }
    _web.isFailingOver = true;
    try {
      final String previousHost = _services.hostManager.currentHost;
      final String nextHost = await _services.hostManager.failover(
        exclude: <String>[previousHost],
      );
      if (nextHost == previousHost) {
        return;
      }
      await _syncHostCookies();
      if (!mounted) {
        return;
      }
      _showNotice('当前入口异常，已切换到备用站点。');
      await _loadUri(
        AppConfig.rewriteToCurrentHost(_currentUri),
        preserveVisiblePage: _page != null,
        sourceTabIndex: _nav.selectedIndex,
        historyMode: NavigationIntent.preserve,
      );
      _web.consecutiveFrameFailures = 0;
    } finally {
      _web.isFailingOver = false;
    }
  }

  Future<bool> _tryRecoverHost(String message) async {
    if (_services.hostManager.sessionPinnedHost != null ||
        !_isRecoverableNetworkError(message)) {
      return false;
    }
    _web.isFailingOver = true;
    final String previousHost = _services.hostManager.currentHost;
    try {
      DebugTrace.log('host.auto_probe_start', <String, Object?>{
        'bootId': _shell.bootId,
        'currentHost': previousHost,
        'message': message,
      });
      await _services.hostManager.refreshProbes(force: true);
      final String nextHost = _services.hostManager.currentHost;
      DebugTrace.log('host.auto_probe_complete', <String, Object?>{
        'bootId': _shell.bootId,
        'previousHost': previousHost,
        'nextHost': nextHost,
      });
      if (nextHost == previousHost) {
        return false;
      }
      await _syncHostCookies();
      if (!mounted) {
        return true;
      }
      _showNotice('网络异常，已自动切换到 $nextHost');
      await _loadUri(
        AppConfig.rewriteToCurrentHost(_currentUri),
        preserveVisiblePage: _page != null,
        sourceTabIndex: _nav.selectedIndex,
        historyMode: NavigationIntent.preserve,
      );
      return true;
    } catch (error) {
      DebugTrace.log('host.auto_probe_failed', <String, Object?>{
        'bootId': _shell.bootId,
        'currentHost': previousHost,
        'message': message,
        'error': error.toString(),
      });
      return false;
    } finally {
      _web.isFailingOver = false;
    }
  }

  bool _isRecoverableNetworkError(String message) {
    final String normalized = message.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    const List<String> networkErrorKeywords = <String>[
      'err_connection_reset',
      'err_connection_closed',
      'err_connection_aborted',
      'err_connection_refused',
      'err_connection_timed_out',
      'err_timed_out',
      'err_name_not_resolved',
      'err_address_unreachable',
      'err_internet_disconnected',
      'err_network_changed',
      'err_proxy_connection_failed',
      'connection reset',
      'connection closed',
      'connection aborted',
      'connection refused',
      'connection timed out',
      'network is unreachable',
      'software caused connection abort',
      'failed to connect',
    ];
    return networkErrorKeywords.any(normalized.contains);
  }

  Future<void> _syncHostCookies() async {
    await _services.session.ensureInitialized();
    if (_services.session.cookies.isEmpty) {
      return;
    }
    if (!PlatformCapabilities.usesMobileWebView) {
      return;
    }
    final WebViewCookieManager? cookieManager = _ui.cookieManager;
    if (cookieManager == null) {
      return;
    }
    // 未变化则跳过 CookieManager 平台调用。
    final String fingerprint = _hostCookieFingerprint();
    if (fingerprint == _shell.syncedHostCookieFingerprint) {
      return;
    }
    for (final MapEntry<String, String> cookie
        in _services.session.cookies.entries) {
      await cookieManager.setCookie(
        WebViewCookie(
          name: cookie.key,
          value: cookie.value,
          domain: _services.hostManager.currentHost,
          path: '/',
        ),
      );
    }
    _shell.syncedHostCookieFingerprint = fingerprint;
  }

  String _hostCookieFingerprint() {
    final List<String> entries =
        _services.session.cookies.entries
            .map(
              (MapEntry<String, String> cookie) =>
                  '${cookie.key}=${cookie.value}',
            )
            .toList()
          ..sort();
    return '${_services.hostManager.currentHost}::${entries.join(';')}';
  }

  Future<void> _clearPlatformCookies() async {
    if (PlatformCapabilities.usesMobileWebView) {
      await _ui.cookieManager?.clearCookies();
      _shell.syncedHostCookieFingerprint = null;
      return;
    }
    if (PlatformCapabilities.supportsDesktopWebView) {
      await DesktopWebViewEnvironment.instance.clearCookies();
      DesktopPageExtractor.instance.invalidateCookiePriming();
    }
  }
}
