part of '../easy_copy_screen.dart';

extension _EasyCopyScreenWebviewPipeline on _EasyCopyScreenState {
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
            final StandardPageLoadHandle<EasyCopyPage>? pendingLoad =
                _pendingPageLoad;
            final bool hasActivePendingLoad =
                pendingLoad != null && !pendingLoad.completer.isCompleted;
            final bool canSurfacePendingLoad =
                hasActivePendingLoad &&
                _canCommitRequest(pendingLoad.requestContext);
            if (_isLoginUri(nextUri)) {
              if (canSurfacePendingLoad) {
                unawaited(_openAuthFlow());
              }
              return NavigationDecision.prevent;
            }
            if (!AppConfig.isAllowedNavigationUri(nextUri)) {
              if (canSurfacePendingLoad) {
                _showSnackBar('已阻止跳转到站外页面');
              }
              return NavigationDecision.prevent;
            }

            final Uri rewrittenUri = AppConfig.rewriteToCurrentHost(
              nextUri ?? _currentUri,
            );
            final StandardPageLoadHandle<EasyCopyPage>? acceptedLoad =
                acceptedPendingNavigationLoad(
                  pendingLoad,
                  rewrittenUri,
                  source: StandardPageLoadEventSource.navigationRequest,
                );
            if (acceptedLoad == null) {
              if (hasActivePendingLoad) {
                _recordDiscardedNavigationCallback(
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
            final StandardPageLoadHandle<EasyCopyPage>? pendingLoad =
                acceptedPendingNavigationLoad(
                  _pendingPageLoad,
                  startedUri,
                  source: StandardPageLoadEventSource.pageStarted,
                );
            if (pendingLoad == null) {
              final StandardPageLoadHandle<EasyCopyPage>? activeLoad =
                  _pendingPageLoad;
              if (activeLoad != null && !activeLoad.completer.isCompleted) {
                _recordDiscardedNavigationCallback(
                  activeLoad.requestContext,
                  phase: 'page-started',
                );
              }
              return;
            }
            _startLoading(startedUri, pendingLoad: pendingLoad);
          },
          onPageFinished: (String url) async {
            final StandardPageLoadHandle<EasyCopyPage>? pendingLoad =
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
              await _controller.runJavaScript(
                buildPageExtractionScript(pendingLoad.loadId),
              );
            } catch (_) {
              if (!mounted ||
                  !_standardPageLoadController.isCurrent(pendingLoad)) {
                _detachPrimaryWebViewIfIdle();
                return;
              }
              _failPendingPageLoad('頁面已加載，但轉換內容失敗。');
            }
          },
          onUrlChange: (UrlChange change) {
            if (change.url == null) {
              return;
            }
            final Uri changedUri = AppConfig.rewriteToCurrentHost(
              Uri.tryParse(change.url!) ?? _currentUri,
            );
            final StandardPageLoadHandle<EasyCopyPage>? pendingLoad =
                acceptedPendingNavigationLoad(
                  _pendingPageLoad,
                  changedUri,
                  source: StandardPageLoadEventSource.urlChange,
                );
            if (pendingLoad != null) {
              _setPendingLocation(changedUri, pendingLoad: pendingLoad);
            } else {
              final StandardPageLoadHandle<EasyCopyPage>? activeLoad =
                  _pendingPageLoad;
              if (activeLoad != null && !activeLoad.completer.isCompleted) {
                _recordDiscardedNavigationCallback(
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
            final StandardPageLoadHandle<EasyCopyPage>? pendingLoad =
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
              _recordDiscardedNavigationCallback(
                pendingLoad.requestContext,
                phase: 'main-frame-error',
              );
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
              _detachDownloadWebViewIfIdle();
              return;
            }
            try {
              await _downloadController.runJavaScript(
                buildPageExtractionScript(loadId),
              );
            } catch (error) {
              _downloadExtractionCompleter?.completeError(error);
              _downloadExtractionCompleter = null;
              _detachDownloadWebViewIfIdle();
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
            _detachDownloadWebViewIfIdle();
          },
        ),
      );
  }

  void _handleBridgeMessage(JavaScriptMessage message) {
    final StandardPageLoadHandle<EasyCopyPage>? pendingLoad = _pendingPageLoad;
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
      final EasyCopyPage page = PageCacheStore.restorePagePayload(payload);
      final Uri pageUri = AppConfig.rewriteToCurrentHost(Uri.parse(page.uri));
      if (!pendingLoad.accepts(
        pageUri,
        source: StandardPageLoadEventSource.payload,
      )) {
        _recordDiscardedNavigationCallback(
          pendingLoad.requestContext,
          phase: 'bridge-payload',
        );
        return;
      }
      _consecutiveFrameFailures = 0;
      pendingLoad.completer.complete(page);
      _standardPageLoadController.clear(pendingLoad);
      _detachPrimaryWebViewIfIdle();
    } catch (_) {
      _failPendingPageLoad('轉換資料解析失敗。');
    }
  }

  void _handleDownloadBridgeMessage(JavaScriptMessage message) {
    final Completer<ReaderPageData>? completer = _downloadExtractionCompleter;
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
      _detachDownloadWebViewIfIdle();
    }
  }

  Future<ReaderPageData> _prepareReaderPageForDownload(Uri uri) async {
    final Uri targetUri = AppConfig.rewriteToCurrentHost(uri);
    return ReaderPageDownloadResolver.resolve(
      targetUri,
      loadFromStorageCache: (Uri chapterUri) {
        return _downloadService.loadCachedReaderPage(chapterUri.toString());
      },
      loadFromPageCache: (Uri chapterUri) async {
        final PageQueryKey key = _pageQueryKeyForUri(chapterUri);
        final CachedPageHit? cachedHit = await _pageRepository.readCached(key);
        final EasyCopyPage? page = cachedHit?.page;
        if (page is ReaderPageData && page.imageUrls.isNotEmpty) {
          return page;
        }
        return null;
      },
      loadFromLightweightSource: (Uri chapterUri) async {
        final EasyCopyPage page = await SiteHtmlPageLoader.instance.loadPage(
          chapterUri,
          authScope: _authScopeForUri(chapterUri),
        );
        if (page is ReaderPageData && page.imageUrls.isNotEmpty) {
          return page;
        }
        throw StateError('章节解析失败');
      },
      loadFromWebViewFallback: _extractReaderPageForDownloadWithWebView,
    );
  }

  Future<ReaderPageData> _extractReaderPageForDownloadWithWebView(
    Uri uri,
  ) async {
    if (_downloadExtractionCompleter != null) {
      throw StateError('正在准备其他章节下载，请稍后再试。');
    }
    await _syncSessionCookiesToCurrentHost();
    final Completer<ReaderPageData> completer = Completer<ReaderPageData>();
    _downloadExtractionCompleter = completer;
    _downloadActiveLoadId += 1;
    await _ensureDownloadWebViewAttached();
    try {
      await _downloadController.loadRequest(
        AppConfig.rewriteToCurrentHost(uri),
      );
    } catch (_) {
      _downloadExtractionCompleter = null;
      _detachDownloadWebViewIfIdle();
      rethrow;
    }
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _downloadExtractionCompleter = null;
        _detachDownloadWebViewIfIdle();
        throw TimeoutException('章节解析超时');
      },
    );
  }

  void _setPrimaryWebViewAttached(bool attached) {
    if (_isPrimaryWebViewAttached == attached) {
      return;
    }
    if (!mounted) {
      _isPrimaryWebViewAttached = attached;
      return;
    }
    _setStateIfMounted(() {
      _isPrimaryWebViewAttached = attached;
    });
  }

  void _setDownloadWebViewAttached(bool attached) {
    if (_isDownloadWebViewAttached == attached) {
      return;
    }
    if (!mounted) {
      _isDownloadWebViewAttached = attached;
      return;
    }
    _setStateIfMounted(() {
      _isDownloadWebViewAttached = attached;
    });
  }

  Future<void> _ensurePrimaryWebViewAttached() async {
    if (_isPrimaryWebViewAttached) {
      return;
    }
    _setPrimaryWebViewAttached(true);
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<void> _ensureDownloadWebViewAttached() async {
    if (_isDownloadWebViewAttached) {
      return;
    }
    _setDownloadWebViewAttached(true);
    await WidgetsBinding.instance.endOfFrame;
  }

  void _detachPrimaryWebViewIfIdle() {
    final StandardPageLoadHandle<EasyCopyPage>? pendingLoad = _pendingPageLoad;
    if (pendingLoad != null && !pendingLoad.completer.isCompleted) {
      return;
    }
    _setPrimaryWebViewAttached(false);
  }

  void _detachDownloadWebViewIfIdle() {
    if (_downloadExtractionCompleter != null) {
      return;
    }
    _setDownloadWebViewAttached(false);
  }

  List<Widget> _buildHiddenWebViewHosts() {
    return <Widget>[
      if (_isPrimaryWebViewAttached)
        _buildHiddenWebViewHost(controller: _controller, left: -8, top: -8),
      if (_isDownloadWebViewAttached)
        _buildHiddenWebViewHost(
          controller: _downloadController,
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
