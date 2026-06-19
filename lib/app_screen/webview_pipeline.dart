part of '../app_screen.dart';

extension _AppScreenWebviewPipeline on _AppScreenState {
  WebViewController get _primaryWebViewController {
    final WebViewController? controller = _controller;
    if (controller == null) {
      throw StateError('当前平台不支持移动端 WebView 管线');
    }
    return controller;
  }

  WebViewController get _downloadWebViewController {
    final WebViewController? controller = _downloadController;
    if (controller == null) {
      throw StateError('当前平台不支持移动端 WebView 管线');
    }
    return controller;
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
            final StandardPageLoadHandle<SitePage>? pendingLoad =
                _pendingPageLoad;
            final bool hasActivePendingLoad =
                pendingLoad != null && !pendingLoad.completer.isCompleted;
            final bool canSurfacePendingLoad =
                hasActivePendingLoad &&
                _canCommitRequest(pendingLoad.requestContext);
            if (isLoginUri(nextUri)) {
              if (canSurfacePendingLoad) {
                unawaited(_openAuthFlow());
              }
              return NavigationDecision.prevent;
            }
            if (!AppConfig.isAllowedNavigationUri(nextUri)) {
              if (canSurfacePendingLoad) {
                _showNotice('已阻止跳转到站外页面');
              }
              return NavigationDecision.prevent;
            }

            final Uri rewrittenUri = AppConfig.rewriteToCurrentHost(
              nextUri ?? _currentUri,
            );
            final StandardPageLoadHandle<SitePage>? acceptedLoad =
                acceptedPendingNavigationLoad(
                  pendingLoad,
                  rewrittenUri,
                  source: StandardPageLoadEventSource.navigationRequest,
                );
            if (acceptedLoad == null) {
              if (hasActivePendingLoad) {
                _recordDiscardedCallback(
                  pendingLoad.requestContext,
                  phase: 'navigation-request',
                );
              }
              return NavigationDecision.prevent;
            }
            _setPendingLocation(rewrittenUri, pendingLoad: acceptedLoad);
            return NavigationDecision.navigate;
          },
          onPageStarted: (String url) {
            final Uri startedUri = AppConfig.rewriteToCurrentHost(
              Uri.tryParse(url) ?? _currentUri,
            );
            final StandardPageLoadHandle<SitePage>? pendingLoad =
                acceptedPendingNavigationLoad(
                  _pendingPageLoad,
                  startedUri,
                  source: StandardPageLoadEventSource.pageStarted,
                );
            if (pendingLoad == null) {
              final StandardPageLoadHandle<SitePage>? activeLoad =
                  _pendingPageLoad;
              if (activeLoad != null && !activeLoad.completer.isCompleted) {
                _recordDiscardedCallback(
                  activeLoad.requestContext,
                  phase: 'page-started',
                );
              }
              return;
            }
            _startLoading(startedUri, pendingLoad: pendingLoad);
          },
          onPageFinished: (String url) async {
            final StandardPageLoadHandle<SitePage>? pendingLoad =
                _pendingPageLoad;
            if (pendingLoad == null || pendingLoad.completer.isCompleted) {
              _detachPrimaryWebViewIfIdle();
              return;
            }
            final Uri finishedUri = AppConfig.rewriteToCurrentHost(
              Uri.tryParse(url) ?? _currentUri,
            );
            if (!pendingLoad.accepts(
              finishedUri,
              source: StandardPageLoadEventSource.pageFinished,
            )) {
              return;
            }
            try {
              await _primaryWebViewController.runJavaScript(
                buildPageExtractionScript(pendingLoad.loadId),
              );
            } catch (_) {
              if (!mounted ||
                  !_standardPageLoadController.isCurrent(pendingLoad)) {
                _detachPrimaryWebViewIfIdle();
                return;
              }
              _failPendingPageLoad('页面已加载，但转换内容失败。');
            }
          },
          onUrlChange: (UrlChange change) {
            if (change.url == null) {
              return;
            }
            final Uri changedUri = AppConfig.rewriteToCurrentHost(
              Uri.tryParse(change.url!) ?? _currentUri,
            );
            final StandardPageLoadHandle<SitePage>? pendingLoad =
                acceptedPendingNavigationLoad(
                  _pendingPageLoad,
                  changedUri,
                  source: StandardPageLoadEventSource.urlChange,
                );
            if (pendingLoad != null) {
              _setPendingLocation(changedUri, pendingLoad: pendingLoad);
            } else {
              final StandardPageLoadHandle<SitePage>? activeLoad =
                  _pendingPageLoad;
              if (activeLoad != null && !activeLoad.completer.isCompleted) {
                _recordDiscardedCallback(
                  activeLoad.requestContext,
                  phase: 'url-change',
                );
              }
            }
          },
          onWebResourceError: (WebResourceError error) {
            if (error.isForMainFrame == false) {
              return;
            }
            final StandardPageLoadHandle<SitePage>? pendingLoad =
                _pendingPageLoad;
            if (pendingLoad == null || pendingLoad.completer.isCompleted) {
              _detachPrimaryWebViewIfIdle();
              return;
            }
            final Uri? failingUri = error.url == null
                ? null
                : Uri.tryParse(error.url!);
            if (failingUri != null &&
                !pendingLoad.accepts(
                  AppConfig.rewriteToCurrentHost(failingUri),
                  source: StandardPageLoadEventSource.mainFrameError,
                )) {
              _recordDiscardedCallback(
                pendingLoad.requestContext,
                phase: 'main-frame-error',
              );
              return;
            }
            unawaited(
              _handleMainFrameFailure(
                error.description.isEmpty ? '页面加载失败，请稍后重试。' : error.description,
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
            final int loadId = _web.downloadActiveLoadId;
            if (_web.downloadExtractionCompleter == null) {
              _detachDownloadWebViewIfIdle();
              return;
            }
            try {
              await _downloadWebViewController.runJavaScript(
                buildPageExtractionScript(loadId),
              );
            } catch (error) {
              _web.downloadExtractionCompleter?.completeError(error);
              _web.downloadExtractionCompleter = null;
              _detachDownloadWebViewIfIdle();
            }
          },
          onWebResourceError: (WebResourceError error) {
            if (error.isForMainFrame == false) {
              return;
            }
            _web.downloadExtractionCompleter?.completeError(
              error.description.isEmpty ? '章节解析失败' : error.description,
            );
            _web.downloadExtractionCompleter = null;
            _detachDownloadWebViewIfIdle();
          },
        ),
      );
  }

  void _handleBridgeMessage(JavaScriptMessage message) {
    final StandardPageLoadHandle<SitePage>? pendingLoad = _pendingPageLoad;
    if (pendingLoad == null || pendingLoad.completer.isCompleted) {
      _detachPrimaryWebViewIfIdle();
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
      if (loadId != pendingLoad.loadId) {
        return;
      }

      payload.remove('loadId');
      final SitePage page = PageCacheStore.restorePagePayload(payload);
      final Uri pageUri = AppConfig.rewriteToCurrentHost(Uri.parse(page.uri));
      if (!pendingLoad.accepts(
        pageUri,
        source: StandardPageLoadEventSource.payload,
      )) {
        _recordDiscardedCallback(
          pendingLoad.requestContext,
          phase: 'bridge-payload',
        );
        return;
      }
      _web.consecutiveFrameFailures = 0;
      pendingLoad.completer.complete(page);
      _standardPageLoadController.clear(pendingLoad);
      _detachPrimaryWebViewIfIdle();
    } catch (_) {
      _failPendingPageLoad('轉換資料解析失敗。');
    }
  }

  void _handleDownloadBridgeMessage(JavaScriptMessage message) {
    final Completer<ReaderPageData>? completer =
        _web.downloadExtractionCompleter;
    if (completer == null || completer.isCompleted) {
      _detachDownloadWebViewIfIdle();
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
      if (loadId != _web.downloadActiveLoadId) {
        return;
      }

      payload.remove('loadId');
      final SitePage page = PageCacheStore.restorePagePayload(payload);
      if (page is ReaderPageData) {
        completer.complete(page);
      } else {
        completer.completeError('章节解析失败');
      }
    } catch (error) {
      completer.completeError(error);
    } finally {
      _web.downloadExtractionCompleter = null;
      _detachDownloadWebViewIfIdle();
    }
  }

  Future<ReaderPageData> _prepareReaderPageForDownload(Uri uri) async {
    final Uri targetUri = AppConfig.rewriteToCurrentHost(uri);
    return ReaderPageDownloadResolver.resolve(
      targetUri,
      loadFromStorageCache: (Uri chapterUri) {
        return _services.downloadService.loadCachedReaderPage(
          chapterUri.toString(),
        );
      },
      loadFromPageCache: (Uri chapterUri) async {
        final PageQueryKey key = _pageQueryKeyForUri(chapterUri);
        final CachedPageHit? cachedHit = await _pageRepository.readCached(key);
        final SitePage? page = cachedHit?.page;
        if (page is ReaderPageData && page.imageUrls.isNotEmpty) {
          return page;
        }
        return null;
      },
      loadFromLightweightSource: (Uri chapterUri) async {
        final SitePage page = await _loadHtmlPageFresh(
          chapterUri,
          authScope: _authScopeForUri(chapterUri),
        );
        if (page is ReaderPageData && page.imageUrls.isNotEmpty) {
          return page;
        }
        throw StateError('章节解析失败');
      },
      loadFromWebViewFallback: _extractDownloadPageWithWebView,
    );
  }

  Future<ReaderPageData> _extractDownloadPageWithWebView(Uri uri) async {
    if (!PlatformCapabilities.usesMobileWebView) {
      final SitePage page = await DesktopPageExtractor.instance.loadPage(
        AppConfig.rewriteToCurrentHost(uri),
      );
      if (page is ReaderPageData) {
        return page;
      }
      throw StateError('章节解析失败');
    }
    if (_web.downloadExtractionCompleter != null) {
      throw StateError('正在准备其他章节下载，请稍后再试。');
    }
    await _syncHostCookies();
    final Completer<ReaderPageData> completer = Completer<ReaderPageData>();
    _web.downloadExtractionCompleter = completer;
    _web.downloadActiveLoadId += 1;
    await _ensureDownloadWebViewAttached();
    try {
      await _downloadWebViewController.loadRequest(
        AppConfig.rewriteToCurrentHost(uri),
      );
    } catch (_) {
      _web.downloadExtractionCompleter = null;
      _detachDownloadWebViewIfIdle();
      rethrow;
    }
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _web.downloadExtractionCompleter = null;
        _detachDownloadWebViewIfIdle();
        throw TimeoutException('章节解析超时');
      },
    );
  }

  void _setPrimaryWebViewAttached(bool attached) {
    if (_web.isPrimaryWebViewAttached == attached) {
      return;
    }
    perfLog('[webview] primary ${attached ? 'attach' : 'detach'}');
    if (!mounted) {
      _web.isPrimaryWebViewAttached = attached;
      return;
    }
    _setStateIfMounted(() {
      _web.isPrimaryWebViewAttached = attached;
    });
  }

  void _setDownloadWebViewAttached(bool attached) {
    if (_web.isDownloadWebViewAttached == attached) {
      return;
    }
    if (!mounted) {
      _web.isDownloadWebViewAttached = attached;
      return;
    }
    _setStateIfMounted(() {
      _web.isDownloadWebViewAttached = attached;
    });
  }

  Future<void> _ensurePrimaryWebViewAttached() async {
    if (!PlatformCapabilities.usesMobileWebView) {
      throw StateError('当前平台不支持移动端 WebView 管线');
    }
    if (_web.isPrimaryWebViewAttached) {
      return;
    }
    _setPrimaryWebViewAttached(true);
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> _ensureDownloadWebViewAttached() async {
    if (!PlatformCapabilities.usesMobileWebView) {
      throw StateError('当前平台不支持移动端 WebView 管线');
    }
    if (_web.isDownloadWebViewAttached) {
      return;
    }
    _setDownloadWebViewAttached(true);
    await WidgetsBinding.instance.endOfFrame;
  }

  void _detachPrimaryWebViewIfIdle() {
    final StandardPageLoadHandle<SitePage>? pendingLoad = _pendingPageLoad;
    if (pendingLoad != null && !pendingLoad.completer.isCompleted) {
      return;
    }
    _setPrimaryWebViewAttached(false);
  }

  void _detachDownloadWebViewIfIdle() {
    if (_web.downloadExtractionCompleter != null) {
      return;
    }
    _setDownloadWebViewAttached(false);
  }

  List<Widget> _buildHiddenWebViewHosts() {
    if (!PlatformCapabilities.usesMobileWebView) {
      return const <Widget>[];
    }
    final WebViewController? controller = _controller;
    final WebViewController? downloadController = _downloadController;
    return <Widget>[
      if (_web.isPrimaryWebViewAttached && controller != null)
        _buildHiddenWebViewHost(controller: controller, left: -8, top: -8),
      if (_web.isDownloadWebViewAttached && downloadController != null)
        _buildHiddenWebViewHost(
          controller: downloadController,
          left: -16,
          top: -16,
        ),
    ];
  }

  Widget _buildHiddenWebViewHost({
    required WebViewController controller,
    required double left,
    required double top,
  }) {
    return Positioned(
      left: left,
      top: top,
      width: 4,
      height: 4,
      child: IgnorePointer(child: WebViewWidget(controller: controller)),
    );
  }
}
