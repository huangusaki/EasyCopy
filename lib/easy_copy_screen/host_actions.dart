part of '../easy_copy_screen.dart';

extension _EasyCopyScreenHostActions on _EasyCopyScreenState {
  Future<void> _refreshHostsInBackgroundAfterBootstrap() {
    final Future<void>? activeTask = _backgroundHostRefreshTask;
    if (activeTask != null) {
      return activeTask;
    }
    final Future<void> refreshTask =
        _refreshHostsInBackgroundAfterBootstrapImpl();
    _backgroundHostRefreshTask = refreshTask;
    return refreshTask.whenComplete(() {
      if (identical(_backgroundHostRefreshTask, refreshTask)) {
        _backgroundHostRefreshTask = null;
      }
    });
  }

  Future<void> _refreshHostsInBackgroundAfterBootstrapImpl() async {
    final String previousHost = _hostManager.currentHost;
    final DateTime? previousCheckedAt = _hostManager.probeSnapshot?.checkedAt;
    DebugTrace.log('host.bootstrap_probe_start', <String, Object?>{
      'bootId': _bootId,
      'currentHost': previousHost,
      'checkedAt': previousCheckedAt?.toIso8601String(),
    });
    try {
      await _hostManager.refreshProbes(force: true);
      final String nextHost = _hostManager.currentHost;
      final DateTime? nextCheckedAt = _hostManager.probeSnapshot?.checkedAt;
      final bool hostChanged = nextHost != previousHost;
      if (hostChanged) {
        await _syncSessionCookiesToCurrentHost();
      }
      DebugTrace.log('host.bootstrap_probe_complete', <String, Object?>{
        'bootId': _bootId,
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
        'bootId': _bootId,
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
        _appVersion = packageInfo.version.trim();
        _appBuildNumber = packageInfo.buildNumber.trim();
        return;
      }
      _setStateIfMounted(() {
        _appVersion = packageInfo.version.trim();
        _appBuildNumber = packageInfo.buildNumber.trim();
      });
    } catch (_) {
      // Keep placeholder values when package info is unavailable.
    }
  }

  Future<void> _checkForUpdates() async {
    if (_isCheckingForUpdates) {
      return;
    }
    if (_appVersion.isEmpty) {
      await _loadAppVersionInfo();
    }
    final String currentVersion = _appVersion.trim();
    if (currentVersion.isEmpty) {
      _showSnackBar('版本信息不可用');
      return;
    }

    _mutateSessionState(() {
      _isCheckingForUpdates = true;
    }, syncSearch: false);
    try {
      final AppUpdateInfo updateInfo = await AppUpdateChecker.instance
          .checkForUpdates(currentVersion: currentVersion);
      if (!mounted) {
        return;
      }
      if (!updateInfo.hasUpdate) {
        _showSnackBar('已是最新版本');
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
        _showSnackBar('检查更新失败');
      }
    } finally {
      if (mounted) {
        _mutateSessionState(() {
          _isCheckingForUpdates = false;
        }, syncSearch: false);
      } else {
        _isCheckingForUpdates = false;
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
        _showSnackBar('打开失败');
      }
    } catch (_) {
      if (mounted) {
        _showSnackBar('打开失败');
      }
    }
  }

  Future<void> _refreshHostSettings() async {
    if (_isUpdatingHostSettings) {
      return;
    }
    _mutateSessionState(() {
      _isUpdatingHostSettings = true;
    }, syncSearch: false);
    try {
      await _hostManager.refreshProbes(force: true);
      await _syncSessionCookiesToCurrentHost();
      if (!mounted) {
        return;
      }
      final bool isPinned = _hostManager.sessionPinnedHost != null;
      _showSnackBar(
        isPinned
            ? '测速完成，当前仍手动锁定到域名 ${_hostManager.currentHost}'
            : '测速完成，已自动选择 ${_hostManager.currentHost}',
      );
    } catch (_) {
      if (mounted) {
        _showSnackBar('测速失败，请稍后重试');
      }
    } finally {
      if (mounted) {
        _mutateSessionState(() {
          _isUpdatingHostSettings = false;
        }, syncSearch: false);
      } else {
        _isUpdatingHostSettings = false;
      }
    }
  }

  Future<void> _selectHost(String host) async {
    final String normalizedHost = host.trim().toLowerCase();
    if (normalizedHost.isEmpty || _isUpdatingHostSettings) {
      return;
    }
    _mutateSessionState(() {
      _isUpdatingHostSettings = true;
    }, syncSearch: false);
    try {
      await _hostManager.pinSessionHost(normalizedHost);
      await _syncSessionCookiesToCurrentHost();
      if (mounted) {
        _showSnackBar('已切换到 $normalizedHost');
      }
    } catch (error) {
      if (mounted) {
        final String message = error is StateError
            ? error.message.toString()
            : '切换域名失败，请稍后重试';
        _showSnackBar(message);
      }
    } finally {
      if (mounted) {
        _mutateSessionState(() {
          _isUpdatingHostSettings = false;
        }, syncSearch: false);
      } else {
        _isUpdatingHostSettings = false;
      }
    }
  }

  Future<void> _useAutomaticHostSelection() async {
    if (_isUpdatingHostSettings) {
      return;
    }
    _mutateSessionState(() {
      _isUpdatingHostSettings = true;
    }, syncSearch: false);
    try {
      await _hostManager.clearSessionPin();
      await _hostManager.refreshProbes(force: true);
      await _syncSessionCookiesToCurrentHost();
      if (mounted) {
        _showSnackBar('已恢复自动选择，当前域名 ${_hostManager.currentHost}');
      }
    } catch (_) {
      if (mounted) {
        _showSnackBar('恢复自动选择失败，请稍后重试');
      }
    } finally {
      if (mounted) {
        _mutateSessionState(() {
          _isUpdatingHostSettings = false;
        }, syncSearch: false);
      } else {
        _isUpdatingHostSettings = false;
      }
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    TopNotice.show(context, message, tone: _topNoticeToneFor(message));
  }

  TopNoticeTone _topNoticeToneFor(String message) {
    final String normalized = message.trim().toLowerCase();
    if (normalized.isEmpty) {
      return TopNoticeTone.info;
    }
    if (normalized.contains('失败') ||
        normalized.contains('异常') ||
        normalized.contains('错误') ||
        normalized.contains('失效') ||
        normalized.contains('不可用')) {
      return TopNoticeTone.error;
    }
    if (normalized.contains('警告') ||
        normalized.contains('稍后') ||
        normalized.contains('阻止')) {
      return TopNoticeTone.warning;
    }
    if (normalized.contains('已') ||
        normalized.contains('完成') ||
        normalized.contains('恢复') ||
        normalized.contains('继续')) {
      return TopNoticeTone.success;
    }
    return TopNoticeTone.info;
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
      _mutateSessionState(() {
        _tabSessionStore.updateCurrent(
          _selectedIndex,
          (PrimaryTabRouteEntry entry) =>
              entry.copyWith(isLoading: false, clearError: true),
        );
      });
      _showSnackBar(message);
    }
    if (_isFailingOver) {
      return;
    }
    if (await _tryAutoRecoverHostOnNetworkFailure(message)) {
      _consecutiveFrameFailures = 0;
      return;
    }
    if (_hostManager.sessionPinnedHost != null ||
        _consecutiveFrameFailures < 2) {
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
        sourceTabIndex: _selectedIndex,
        historyMode: NavigationIntent.preserve,
      );
      _consecutiveFrameFailures = 0;
    } finally {
      _isFailingOver = false;
    }
  }

  Future<bool> _tryAutoRecoverHostOnNetworkFailure(String message) async {
    if (_hostManager.sessionPinnedHost != null ||
        !_isLikelyRecoverableNetworkFailure(message)) {
      return false;
    }
    _isFailingOver = true;
    final String previousHost = _hostManager.currentHost;
    try {
      DebugTrace.log('host.auto_probe_start', <String, Object?>{
        'bootId': _bootId,
        'currentHost': previousHost,
        'message': message,
      });
      await _hostManager.refreshProbes(force: true);
      final String nextHost = _hostManager.currentHost;
      DebugTrace.log('host.auto_probe_complete', <String, Object?>{
        'bootId': _bootId,
        'previousHost': previousHost,
        'nextHost': nextHost,
      });
      if (nextHost == previousHost) {
        return false;
      }
      await _syncSessionCookiesToCurrentHost();
      if (!mounted) {
        return true;
      }
      _showSnackBar('网络异常，已自动切换到 $nextHost');
      await _loadUri(
        AppConfig.rewriteToCurrentHost(_currentUri),
        preserveVisiblePage: _page != null,
        sourceTabIndex: _selectedIndex,
        historyMode: NavigationIntent.preserve,
      );
      return true;
    } catch (error) {
      DebugTrace.log('host.auto_probe_failed', <String, Object?>{
        'bootId': _bootId,
        'currentHost': previousHost,
        'message': message,
        'error': error.toString(),
      });
      return false;
    } finally {
      _isFailingOver = false;
    }
  }

  bool _isLikelyRecoverableNetworkFailure(String message) {
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
}
