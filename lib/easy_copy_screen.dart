import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_copy/config/app_config.dart';
import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/services/host_manager.dart';
import 'package:easy_copy/services/image_cache.dart';
import 'package:easy_copy/services/page_cache_store.dart';
import 'package:easy_copy/services/page_probe_service.dart';
import 'package:easy_copy/services/site_api_client.dart';
import 'package:easy_copy/services/site_session.dart';
import 'package:easy_copy/webview/page_extractor_script.dart';
import 'package:easy_copy/widgets/auth_webview_screen.dart';
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
  final WebViewCookieManager _cookieManager = WebViewCookieManager();
  final TextEditingController _searchController = TextEditingController();
  final HostManager _hostManager = HostManager.instance;
  final SiteSession _session = SiteSession.instance;
  final PageCacheStore _cacheStore = PageCacheStore.instance;
  final PageProbeService _probeService = PageProbeService.instance;
  final SiteApiClient _apiClient = SiteApiClient.instance;

  Uri _currentUri = AppConfig.resolvePath('/');
  EasyCopyPage? _page;
  String? _errorMessage;
  bool _isLoading = true;
  int _selectedIndex = 0;
  int _activeLoadId = 0;
  bool _preservePageOnNextLoad = false;
  bool _isFailingOver = false;
  int _consecutiveFrameFailures = 0;
  bool _isDiscoverThemeExpanded = false;

  @override
  void initState() {
    super.initState();
    _controller = _buildController();
    unawaited(_bootstrap());
    _syncSearchController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await Future.wait(<Future<void>>[
      _hostManager.ensureInitialized(),
      _session.ensureInitialized(),
      _cacheStore.ensureInitialized(),
    ]);
    final Uri homeUri = appDestinations.first.uri;
    if (!mounted) {
      return;
    }
    setState(() {
      _currentUri = homeUri;
      _selectedIndex = tabIndexForUri(homeUri);
    });
    _syncSearchController();
    await _loadUri(homeUri);
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
              preserveCurrentPage: _preservePageOnNextLoad,
            );
            _preservePageOnNextLoad = false;
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
              setState(() {
                _isLoading = false;
                _errorMessage = '頁面已加載，但轉換內容失敗。';
              });
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

  void _handleBridgeMessage(JavaScriptMessage message) {
    try {
      final Object? decoded = jsonDecode(message.message);
      if (decoded is! Map) {
        return;
      }

      final Map<String, Object?> payload = decoded.map(
        (Object? key, Object? value) => MapEntry(key.toString(), value),
      );

      final int loadId = (payload['loadId'] as num?)?.toInt() ?? -1;
      if (loadId != _activeLoadId) {
        return;
      }

      payload.remove('loadId');
      final EasyCopyPage page = PageCacheStore.restorePagePayload(payload);
      if (!mounted) {
        return;
      }

      _consecutiveFrameFailures = 0;
      setState(() {
        _page = page;
        _isLoading = false;
        _errorMessage = null;
        _currentUri = AppConfig.rewriteToCurrentHost(Uri.parse(page.uri));
        _selectedIndex = tabIndexForUri(_currentUri);
      });
      if (page is ReaderPageData) {
        unawaited(EasyCopyImageCaches.prefetchReaderImages(page.imageUrls));
      }
      _syncSearchController();
      if (page is! UnknownPageData) {
        unawaited(
          _cacheStore.writeEnvelope(
            PageCacheStore.buildEnvelope(
              routeKey: AppConfig.routeKeyForUri(Uri.parse(page.uri)),
              page: page,
              fingerprint: _fingerprintForPage(page),
              authScope: 'guest',
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _errorMessage = '轉換資料解析失敗。';
      });
    }
  }

  void _setPendingLocation(Uri uri) {
    final Uri rewrittenUri = AppConfig.rewriteToCurrentHost(uri);
    if (!mounted) {
      _currentUri = rewrittenUri;
      _selectedIndex = tabIndexForUri(rewrittenUri);
      return;
    }

    setState(() {
      _currentUri = rewrittenUri;
      _selectedIndex = tabIndexForUri(rewrittenUri);
    });
    _syncSearchController();
  }

  void _startLoading(Uri uri, {required bool preserveCurrentPage}) {
    _activeLoadId += 1;
    final Uri rewrittenUri = AppConfig.rewriteToCurrentHost(uri);
    if (!mounted) {
      _currentUri = rewrittenUri;
      _selectedIndex = tabIndexForUri(rewrittenUri);
      _isLoading = true;
      _errorMessage = null;
      if (!preserveCurrentPage) {
        _page = null;
      }
      return;
    }

    setState(() {
      _currentUri = rewrittenUri;
      _selectedIndex = tabIndexForUri(rewrittenUri);
      _isLoading = true;
      _errorMessage = null;
      if (!preserveCurrentPage) {
        _page = null;
      }
    });
    _syncSearchController();
  }

  Future<void> _beginWebLoad(
    Uri uri, {
    bool preserveVisiblePage = false,
  }) async {
    final Uri targetUri = AppConfig.rewriteToCurrentHost(uri);
    _preservePageOnNextLoad = preserveVisiblePage;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _currentUri = targetUri;
        _selectedIndex = tabIndexForUri(targetUri);
        if (!preserveVisiblePage) {
          _page = null;
        }
      });
    }
    await _syncSessionCookiesToCurrentHost();
    await _controller.loadRequest(targetUri);
  }

  Future<void> _loadUri(
    Uri uri, {
    bool bypassCache = false,
    bool preserveVisiblePage = false,
  }) async {
    await _hostManager.ensureInitialized();
    final Uri targetUri = AppConfig.rewriteToCurrentHost(uri);
    if (_isLoginUri(targetUri)) {
      await _openAuthFlow();
      return;
    }
    if (_isProfileUri(targetUri)) {
      await _loadProfilePage(forceRefresh: bypassCache);
      return;
    }
    if (!AppConfig.isAllowedNavigationUri(targetUri)) {
      _showSnackBar('已阻止跳转到站外页面');
      return;
    }

    _consecutiveFrameFailures = 0;
    _setPendingLocation(targetUri);
    final String routeKey = AppConfig.routeKeyForUri(targetUri);
    if (!bypassCache) {
      final CachedPageEnvelope? cachedEntry = await _cacheStore.read(
        routeKey,
        authScope: 'guest',
      );
      if (cachedEntry != null) {
        final EasyCopyPage cachedPage = PageCacheStore.restorePage(cachedEntry);
        if (!mounted) {
          return;
        }
        setState(() {
          _page = cachedPage;
          _currentUri = targetUri;
          _selectedIndex = tabIndexForUri(targetUri);
          _errorMessage = null;
          _isLoading = false;
        });
        if (cachedPage is ReaderPageData) {
          unawaited(
            EasyCopyImageCaches.prefetchReaderImages(cachedPage.imageUrls),
          );
        }
        if (!cachedEntry.isSoftExpired(DateTime.now())) {
          return;
        }
        setState(() {
          _isLoading = true;
        });
        unawaited(_revalidateCachedPage(targetUri, cachedEntry));
        return;
      }
    }
    await _beginWebLoad(
      targetUri,
      preserveVisiblePage: preserveVisiblePage,
    );
  }

  Future<void> _revalidateCachedPage(
    Uri uri,
    CachedPageEnvelope cachedEntry,
  ) async {
    try {
      final PageProbeResult probe = await _probeService.probe(uri);
      if (!mounted || AppConfig.routeKeyForUri(_currentUri) != cachedEntry.routeKey) {
        return;
      }
      if (probe.fingerprint == cachedEntry.fingerprint) {
        await _cacheStore.refreshValidation(
          cachedEntry.routeKey,
          authScope: cachedEntry.authScope,
        );
        if (!mounted) {
          return;
        }
        setState(() {
          _isLoading = false;
          _errorMessage = null;
        });
        return;
      }
      await _beginWebLoad(uri, preserveVisiblePage: true);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadProfilePage({bool forceRefresh = false}) async {
    final Uri profileUri = AppConfig.profileUri;
    _setPendingLocation(profileUri);
    if (!_session.isAuthenticated) {
      if (!mounted) {
        return;
      }
      setState(() {
        _page = ProfilePageData.loggedOut(uri: profileUri.toString());
        _isLoading = false;
        _errorMessage = null;
      });
      return;
    }

    final String authScope = _session.authScope;
    if (!forceRefresh) {
      final CachedPageEnvelope? cachedEntry = await _cacheStore.read(
        AppConfig.profileRouteKey,
        authScope: authScope,
      );
      if (cachedEntry != null) {
        final ProfilePageData cachedPage =
            PageCacheStore.restorePage(cachedEntry) as ProfilePageData;
        if (!mounted) {
          return;
        }
        setState(() {
          _page = cachedPage;
          _isLoading = false;
          _errorMessage = null;
        });
        if (!cachedEntry.isSoftExpired(DateTime.now())) {
          return;
        }
        setState(() {
          _isLoading = true;
        });
        unawaited(_refreshProfileInBackground(cachedEntry.authScope));
        return;
      }
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      final ProfilePageData profilePage = await _fetchAndStoreProfile();
      if (!mounted) {
        return;
      }
      setState(() {
        _page = profilePage;
        _isLoading = false;
      });
    } catch (error) {
      await _handleProfileLoadFailure(error);
    }
  }

  Future<void> _refreshProfileInBackground(String authScope) async {
    try {
      final ProfilePageData profilePage = await _fetchAndStoreProfile();
      if (!mounted) {
        return;
      }
      setState(() {
        _page = profilePage;
        _isLoading = false;
        _errorMessage = null;
      });
      await _cacheStore.refreshValidation(
        AppConfig.profileRouteKey,
        authScope: authScope,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<ProfilePageData> _fetchAndStoreProfile() async {
    final ProfilePageData profilePage = await _apiClient.loadProfile();
    final String authScope = profilePage.isLoggedIn ? _session.authScope : 'guest';
    await _cacheStore.writeEnvelope(
      PageCacheStore.buildEnvelope(
        routeKey: AppConfig.profileRouteKey,
        page: profilePage,
        fingerprint: _fingerprintForPage(profilePage),
        authScope: authScope,
      ),
    );
    return profilePage;
  }

  Future<void> _handleProfileLoadFailure(Object error) async {
    final String message = error.toString();
    if (message.contains('登录已失效')) {
      await _logout(showFeedback: false);
      if (!mounted) {
        return;
      }
      setState(() {
        _page = ProfilePageData.loggedOut(uri: AppConfig.profileUri.toString());
        _isLoading = false;
        _errorMessage = null;
      });
      _showSnackBar('登录已失效，请重新登录。');
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _isLoading = false;
      _errorMessage = _page == null ? message : null;
    });
    if (_page != null) {
      _showSnackBar(message);
    }
  }

  Future<void> _retryCurrentPage() async {
    if (_page is ProfilePageData || _selectedIndex == 3) {
      await _loadProfilePage(forceRefresh: true);
      return;
    }
    await _loadUri(
      _currentUri,
      bypassCache: true,
      preserveVisiblePage: _page != null,
    );
  }

  Future<void> _loadHome() async {
    await _loadUri(appDestinations.first.uri);
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
          return AuthWebViewScreen(
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
    await _loadProfilePage(forceRefresh: true);
  }

  Future<void> _logout({bool showFeedback = true}) async {
    await _cacheStore.removeAuthenticatedEntries();
    await _session.clear();
    await _hostManager.clearSessionPin();
    await _cookieManager.clearCookies();
    if (!mounted) {
      return;
    }
    setState(() {
      _page = ProfilePageData.loggedOut(uri: AppConfig.profileUri.toString());
      _currentUri = AppConfig.profileUri;
      _selectedIndex = 3;
      _isLoading = false;
      _errorMessage = null;
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

  Future<void> _onItemTapped(int index) async {
    if (index < 0 || index >= appDestinations.length) {
      return;
    }
    if (index == 3) {
      await _loadProfilePage();
      return;
    }
    await _loadUri(appDestinations[index].uri);
  }

  Future<void> _handleBackNavigation() async {
    if (_page is ProfilePageData && _selectedIndex == 3) {
      await _loadHome();
      return;
    }
    if (await _controller.canGoBack()) {
      await _controller.goBack();
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
    if (_page == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = message;
      });
    } else {
      setState(() {
        _isLoading = false;
      });
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

  bool get _isReaderMode => _page is ReaderPageData;

  bool get _shouldShowSearchBar => _page is! ProfilePageData;

  bool get _shouldShowBackButton {
    final EasyCopyPage? page = _page;
    if (page is DetailPageData || page is UnknownPageData) {
      return true;
    }
    if (page is DiscoverPageData && _currentUri.path == '/search') {
      return true;
    }
    return false;
  }

  String get _pageTitle {
    final EasyCopyPage? page = _page;
    if (page == null) {
      return appDestinations[_selectedIndex].label;
    }
    return page.title;
  }

  String get _pageSubtitle {
    final EasyCopyPage? page = _page;
    if (_errorMessage != null) {
      return '原网页保持隐藏，仅展示转换后的状态层。';
    }
    if (page != null && _isLoading) {
      return '正在后台检查内容是否有更新。';
    }
    if (page == null) {
      return '正在后台整理桌面页面内容，前台只保留移动端界面。';
    }
    switch (page.type) {
      case EasyCopyPageType.home:
        return '首页内容重新排版，直接进入可读状态。';
      case EasyCopyPageType.discover:
        return '筛选、列表和分页都按手机浏览节奏重构。';
      case EasyCopyPageType.rank:
        return '榜单信息展开成纵向卡片，避免桌面三栏压缩。';
      case EasyCopyPageType.detail:
        return '详情和目录已拆成移动端信息结构。';
      case EasyCopyPageType.reader:
        return '阅读页已切换为原生图片流。';
      case EasyCopyPageType.profile:
        return page is ProfilePageData && page.isLoggedIn
            ? '收藏、历史和继续阅读都走原生接口。'
            : '登录后在原生界面查看收藏与浏览历史。';
      case EasyCopyPageType.unknown:
        return '当前页面还没有完成原生支持。';
    }
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

  String _fingerprintForPage(EasyCopyPage page) {
    switch (page) {
      case HomePageData homePage:
        final List<ComicCardData> cards = homePage.sections
            .expand((ComicSectionData section) => section.items)
            .toList(growable: false);
        return <String>[
          Uri.parse(homePage.uri).path,
          Uri.parse(homePage.uri).query,
          '',
          cards.isEmpty ? '' : '${cards.first.title}::${cards.first.href}',
          cards.isEmpty ? '' : '${cards.last.title}::${cards.last.href}',
          '${cards.length}',
        ].join('::');
      case DiscoverPageData discoverPage:
        final List<String> activeFilters = discoverPage.filters
            .expand((FilterGroupData group) => group.options)
            .where((LinkAction option) => option.active)
            .map((LinkAction option) => option.label)
            .followedBy(
              discoverPage.pager.currentLabel.isEmpty
                  ? const Iterable<String>.empty()
                  : <String>[discoverPage.pager.currentLabel],
            )
            .toList(growable: false);
        return <String>[
          Uri.parse(discoverPage.uri).path,
          Uri.parse(discoverPage.uri).query,
          activeFilters.join('|'),
          discoverPage.items.isEmpty
              ? ''
              : '${discoverPage.items.first.title}::${discoverPage.items.first.href}',
          discoverPage.items.isEmpty
              ? ''
              : '${discoverPage.items.last.title}::${discoverPage.items.last.href}',
          '${discoverPage.items.length}',
        ].join('::');
      case RankPageData rankPage:
        final List<LinkAction> activeTabs = <LinkAction>[
          ...rankPage.categories.where((LinkAction item) => item.active),
          ...rankPage.periods.where((LinkAction item) => item.active),
        ];
        return <String>[
          Uri.parse(rankPage.uri).path,
          activeTabs.map((LinkAction item) => item.label).join('|'),
          rankPage.items.isEmpty
              ? ''
              : '${rankPage.items.first.title}::${rankPage.items.first.href}',
          rankPage.items.isEmpty
              ? ''
              : '${rankPage.items.last.title}::${rankPage.items.last.href}',
          '${rankPage.items.length}',
        ].join('::');
      case DetailPageData detailPage:
        final List<ChapterData> chapters = detailPage.chapterGroups.isNotEmpty
            ? detailPage.chapterGroups
                  .expand((ChapterGroupData group) => group.chapters)
                  .toList(growable: false)
            : detailPage.chapters;
        return <String>[
          Uri.parse(detailPage.uri).path,
          detailPage.updatedAt,
          detailPage.status,
          '${chapters.length}',
          chapters.isEmpty ? '' : chapters.first.href,
          chapters.isEmpty ? '' : chapters.last.href,
        ].join('::');
      case ReaderPageData readerPage:
        return <String>[
          Uri.parse(readerPage.uri).path,
          readerPage.title,
          readerPage.progressLabel,
          readerPage.contentKey,
        ].join('::');
      case ProfilePageData profilePage:
        return <String>[
          profilePage.user?.userId ?? '',
          '${profilePage.collections.length}',
          '${profilePage.history.length}',
          profilePage.continueReading?.chapterHref ?? '',
        ].join('::');
      case UnknownPageData unknownPage:
        return <String>[unknownPage.uri, unknownPage.message].join('::');
    }
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
                  key: ValueKey<String>(
                    '${_page?.type.name ?? 'loading'}-${_currentUri.toString()}',
                  ),
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
      _buildHeaderCard(
        context,
        title: _pageTitle,
        subtitle: _pageSubtitle,
        showBackButton: _shouldShowBackButton,
        showSearchBar: _shouldShowSearchBar,
      ),
      const SizedBox(height: 18),
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

  List<Widget> _buildProfileSections(ProfilePageData page) {
    return <Widget>[
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
      ),
    ];
  }

  Widget _buildHeaderCard(
    BuildContext context, {
    required String title,
    required String subtitle,
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 22,
                          height: 1.1,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF18202A),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: _retryCurrentPage,
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFFF2F5F8),
                    foregroundColor: colorScheme.primary,
                  ),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            if (showSearchBar) ...<Widget>[
              const SizedBox(height: 14),
              Container(
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
              ),
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
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: <Widget>[
        _buildHeaderCard(
          context,
          title: _pageTitle,
          subtitle: _pageSubtitle,
          showBackButton: _shouldShowBackButton,
          showSearchBar: _shouldShowSearchBar,
        ),
        const SizedBox(height: 18),
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
                actionLabel:
                    _isDiscoverThemeExpanded ? '收起分類' : '查看全部分類',
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
            children: <Widget>[
              if (page.categories.isNotEmpty)
                _LinkChipWrap(items: page.categories, onTap: _navigateToHref),
              if (page.categories.isNotEmpty && page.periods.isNotEmpty)
                const SizedBox(height: 14),
              if (page.periods.isNotEmpty)
                _LinkChipWrap(items: page.periods, onTap: _navigateToHref),
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
          children: page.items
              .map(
                (RankEntryData item) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _RankCard(
                    item: item,
                    onTap: () => _navigateToHref(item.href),
                  ),
                ),
              )
              .toList(growable: false),
        ),
      ),
    );

    return sections;
  }

  List<Widget> _buildDetailSections(DetailPageData page) {
    final List<Widget> sections = <Widget>[
      _DetailHeroCard(
        page: page,
        onReadNow: page.startReadingHref.isNotEmpty
            ? () => _navigateToHref(page.startReadingHref)
            : null,
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
          _ChapterGrid(chapters: group.chapters, onTap: _navigateToHref),
        );
        chapterWidgets.add(const SizedBox(height: 18));
      }
    } else if (page.chapters.isNotEmpty) {
      chapterWidgets.add(
        _ChapterGrid(chapters: page.chapters, onTap: _navigateToHref),
      );
    }

    sections.add(
      _SurfaceBlock(
        title: '章節目錄',
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
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: <Widget>[
                      IconButton.filledTonal(
                        onPressed: _handleBackNavigation,
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              page.comicTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              page.chapterTitle.isEmpty
                                  ? page.progressLabel
                                  : '${page.chapterTitle} ${page.progressLabel}'
                                        .trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (page.catalogHref.isNotEmpty)
                        IconButton.filledTonal(
                          onPressed: () => _navigateToHref(page.catalogHref),
                          icon: const Icon(Icons.menu_book_rounded),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _retryCurrentPage,
                child: ListView.builder(
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
                                (
                                  BuildContext context,
                                  String url,
                                  Object error,
                                ) {
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
          ],
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
            _NetworkImageBox(
              imageUrl: banner.imageUrl,
              aspectRatio: 1,
            ),
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

class _LinkChipWrap extends StatelessWidget {
  const _LinkChipWrap({required this.items, required this.onTap});

  final List<LinkAction> items;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
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
    required this.onTagTap,
  });

  final DetailPageData page;
  final VoidCallback? onReadNow;
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
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onReadNow,
              icon: const Icon(Icons.chrome_reader_mode_rounded),
              label: const Text('开始阅读'),
            ),
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
  const _ChapterGrid({required this.chapters, required this.onTap});

  final List<ChapterData> chapters;
  final ValueChanged<String> onTap;

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
        return InkWell(
          onTap: () => onTap(chapter.href),
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F6F8),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                chapter.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        );
      },
    );
  }
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
                errorWidget:
                    (
                      BuildContext context,
                      String url,
                      Object error,
                    ) {
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
