import 'dart:async';
import 'dart:convert';

import 'package:easy_copy/config/app_config.dart';
import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/webview/page_extractor_script.dart';
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
  final TextEditingController _searchController = TextEditingController();

  Uri _currentUri = appDestinations.first.uri;
  EasyCopyPage? _page;
  String? _errorMessage;
  bool _isLoading = true;
  int _selectedIndex = 0;
  int _activeLoadId = 0;

  @override
  void initState() {
    super.initState();
    _selectedIndex = tabIndexForUri(_currentUri);
    _controller = _buildController();
    _controller.loadRequest(_currentUri);
    _syncSearchController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
            if (!AppConfig.isAllowedNavigationUri(nextUri)) {
              _showSnackBar('已阻止跳转到站外页面');
              return NavigationDecision.prevent;
            }

            _setPendingLocation(nextUri ?? _currentUri);
            return NavigationDecision.navigate;
          },
          onPageStarted: (String url) {
            _startLoading(Uri.tryParse(url) ?? _currentUri);
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

            setState(() {
              _isLoading = false;
              _errorMessage = error.description.isEmpty
                  ? '頁面加載失敗，請稍後重試。'
                  : error.description;
            });
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

      final EasyCopyPage page = EasyCopyPage.fromJson(payload);
      if (!mounted) {
        return;
      }

      setState(() {
        _page = page;
        _isLoading = false;
        _errorMessage = null;
        _currentUri = Uri.parse(page.uri);
        _selectedIndex = tabIndexForUri(_currentUri);
      });
      _syncSearchController();
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
    if (!mounted) {
      _currentUri = uri;
      _selectedIndex = tabIndexForUri(uri);
      return;
    }

    setState(() {
      _currentUri = uri;
      _selectedIndex = tabIndexForUri(uri);
    });
    _syncSearchController();
  }

  void _startLoading(Uri uri) {
    _activeLoadId += 1;
    if (!mounted) {
      _currentUri = uri;
      _selectedIndex = tabIndexForUri(uri);
      _isLoading = true;
      _errorMessage = null;
      _page = null;
      return;
    }

    setState(() {
      _currentUri = uri;
      _selectedIndex = tabIndexForUri(uri);
      _isLoading = true;
      _errorMessage = null;
      _page = null;
    });
    _syncSearchController();
  }

  Future<void> _loadUri(Uri uri) async {
    if (!AppConfig.isAllowedNavigationUri(uri)) {
      _showSnackBar('已阻止跳转到站外页面');
      return;
    }

    _setPendingLocation(uri);
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _page = null;
    });
    await _controller.loadRequest(uri);
  }

  Future<void> _retryCurrentPage() async {
    await _loadUri(_currentUri);
  }

  Future<void> _loadHome() async {
    await _loadUri(appDestinations.first.uri);
  }

  void _navigateToHref(String href) {
    if (href.trim().isEmpty) {
      return;
    }
    final Uri targetUri = AppConfig.resolveNavigationUri(
      href,
      currentUri: _currentUri,
    );
    unawaited(_loadUri(targetUri));
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
    await _loadUri(appDestinations[index].uri);
  }

  Future<void> _handleBackNavigation() async {
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

  bool get _isReaderMode => _page is ReaderPageData;

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
    if (_isLoading || page == null) {
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
        return '个人中心仍在重构中。';
      case EasyCopyPageType.unknown:
        return '当前页面还没有完成原生支持。';
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
        child: _errorMessage != null
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
      ),
      const SizedBox(height: 18),
    ];

    if (_isLoading || _page == null) {
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
        children.addAll(_buildMessageSections(profilePage.message));
      case UnknownPageData unknownPage:
        children.addAll(_buildMessageSections(unknownPage.message));
      case ReaderPageData _:
        break;
    }

    return children;
  }

  Widget _buildHeaderCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool showBackButton,
  }) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[Color(0xFF0E8B84), Color(0xFF2D6CF4)],
        ),
      ),
      child: Stack(
        children: <Widget>[
          Positioned(
            top: -20,
            right: -12,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const SizedBox(width: 132, height: 132),
            ),
          ),
          Positioned(
            bottom: -24,
            left: -16,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const SizedBox(width: 108, height: 108),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    if (showBackButton)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: IconButton.filledTonal(
                          onPressed: _handleBackNavigation,
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.16,
                            ),
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'EasyCopy',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              height: 1.05,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.86),
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: _retryCurrentPage,
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.16),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
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
            ),
          ),
        ],
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
          child: SizedBox(
            height: 220,
            child: ListView.separated(
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
      sections.add(
        _SurfaceBlock(
          title: '篩選器',
          child: Column(
            children: page.filters
                .map(
                  (FilterGroupData group) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _FilterGroup(group: group, onTap: _navigateToHref),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      );
      sections.add(const SizedBox(height: 18));
    }

    if (page.spotlight.isNotEmpty) {
      sections.add(
        _SurfaceBlock(
          title: '今日推荐',
          child: SizedBox(
            height: 228,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: page.spotlight.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (BuildContext context, int index) {
                final ComicCardData item = page.spotlight[index];
                return SizedBox(
                  width: 148,
                  child: _CompactComicCard(
                    item: item,
                    onTap: () => _navigateToHref(item.href),
                  ),
                );
              },
            ),
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
            ? () => _navigateToHref(page.pager.prevHref)
            : null,
        onNext: page.pager.hasNext
            ? () => _navigateToHref(page.pager.nextHref)
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
                          child: Image.network(
                            page.imageUrls[index],
                            fit: BoxFit.fitWidth,
                            width: double.infinity,
                            loadingBuilder:
                                (
                                  BuildContext context,
                                  Widget child,
                                  ImageChunkEvent? loadingProgress,
                                ) {
                                  if (loadingProgress == null) {
                                    return child;
                                  }
                                  return SizedBox(
                                    height: 260,
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        value:
                                            loadingProgress
                                                    .expectedTotalBytes ==
                                                null
                                            ? null
                                            : loadingProgress
                                                      .cumulativeBytesLoaded /
                                                  loadingProgress
                                                      .expectedTotalBytes!,
                                      ),
                                    ),
                                  );
                                },
                            errorBuilder:
                                (
                                  BuildContext context,
                                  Object error,
                                  StackTrace? stackTrace,
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
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
    );
  }
}

class _HeroBannerCard extends StatelessWidget {
  const _HeroBannerCard({required this.banner, required this.onTap});

  final HeroBannerData banner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: const Color(0xFF102038),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: _NetworkImageBox(
                imageUrl: banner.imageUrl,
                aspectRatio: 1,
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: const LinearGradient(
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
        childAspectRatio: 0.52,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
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
              style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
            ),
          ],
          if (item.secondaryText.isNotEmpty) ...<Widget>[
            const SizedBox(height: 3),
            Text(
              item.secondaryText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }
}

class _CompactComicCard extends StatelessWidget {
  const _CompactComicCard({required this.item, required this.onTap});

  final ComicCardData item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: _NetworkImageBox(imageUrl: item.coverUrl, aspectRatio: 0.72),
          ),
          const SizedBox(height: 8),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 3),
          Text(
            item.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _FilterGroup extends StatelessWidget {
  const _FilterGroup({required this.group, required this.onTap});

  final FilterGroupData group;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(group.label, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
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
        ? const Color(0xFF0E8B84)
        : const Color(0xFFF2F3F5);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : const Color(0xFF313742),
            fontWeight: FontWeight.w700,
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
            : Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder:
                    (
                      BuildContext context,
                      Object error,
                      StackTrace? stackTrace,
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
