part of '../easy_copy_screen.dart';

extension _EasyCopyScreenRouteClassifiers on _EasyCopyScreenState {
  bool get _isDetailRoute {
    final EasyCopyPage? page = _page;
    if (page is DetailPageData) {
      return true;
    }
    return _isDetailCatalogUri(_currentUri);
  }

  bool get _shouldShowSearchBar {
    final EasyCopyPage? page = _page;
    if (page is ProfilePageData ||
        page is DetailPageData ||
        _isProfileUri(_currentUri) ||
        _isTopicUri(_currentUri)) {
      return false;
    }
    return !_isDetailRoute;
  }

  bool get _isPrimaryTabContent {
    if (_isTopicListUri(_currentUri)) {
      return true;
    }
    if (_shouldShowBackButton) {
      return false;
    }
    final EasyCopyPage? page = _page;
    return page == null ||
        page is HomePageData ||
        page is DiscoverPageData ||
        page is RankPageData ||
        page is ProfilePageData;
  }

  bool get _shouldShowHeaderCard =>
      !_isPrimaryTabContent &&
      !_isDetailRoute &&
      !_isSecondaryProfileRoute &&
      !_shouldHideSecondaryDiscoverHeaderCard;

  bool get _shouldHideSecondaryDiscoverHeaderCard {
    if (!_isSecondaryDiscoverRoute) {
      return false;
    }
    final String path = _currentUri.path.toLowerCase();
    return path.startsWith('/recommend') || path.startsWith('/newest');
  }

  bool get _shouldShowBackButton {
    final EasyCopyPage? page = _page;
    if (_isSecondaryDiscoverRoute) {
      return true;
    }
    if (_isSecondaryProfileRoute) {
      return true;
    }
    if (page is DetailPageData || page is UnknownPageData || _isDetailRoute) {
      return true;
    }
    if ((page is DiscoverPageData || page == null) &&
        _currentUri.path == '/search') {
      return true;
    }
    return false;
  }

  bool _isPrimaryDiscoverUri(Uri uri) {
    final String path = uri.path.toLowerCase();
    return path.startsWith('/comics') ||
        path.startsWith('/filter') ||
        path.startsWith('/search');
  }

  bool _isDiscoverUri(Uri uri) {
    final String path = uri.path.toLowerCase();
    return path.startsWith('/comics') ||
        path.startsWith('/filter') ||
        path.startsWith('/search') ||
        path.startsWith('/topic') ||
        path.startsWith('/recommend') ||
        path.startsWith('/newest');
  }

  bool _isTopicUri(Uri uri) {
    return uri.path.toLowerCase().startsWith('/topic');
  }

  bool _isTopicListUri(Uri uri) {
    final String path = uri.path.toLowerCase();
    return path == '/topic' || path == '/topic/';
  }

  bool get _isSecondaryDiscoverRoute {
    return _isDiscoverUri(_currentUri) && !_isPrimaryDiscoverUri(_currentUri);
  }

  bool get _isSecondaryProfileRoute {
    return _isProfileUri(_currentUri) &&
        AppConfig.profileSubviewForUri(_currentUri) != ProfileSubview.root;
  }

  String get _pageTitle {
    if (_isProfileUri(_currentUri)) {
      return AppConfig.profileSubviewTitle(
        AppConfig.profileSubviewForUri(_currentUri),
      );
    }
    if (_isTopicListUri(_currentUri)) {
      return '专题精选';
    }
    final EasyCopyPage? page = _page;
    if (page == null) {
      if (_isDetailRoute) {
        return '漫畫詳情';
      }
      return appDestinations[_selectedIndex].label;
    }
    return page.title;
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

  bool _isDetailCatalogUri(Uri uri) {
    final String path = uri.path.toLowerCase();
    return path.startsWith('/comic/') && !path.contains('/chapter/');
  }

  bool _isUserScopedDetailUri(Uri uri) {
    return _session.isAuthenticated && _isDetailCatalogUri(uri);
  }

  Uri get _visiblePageUriForTransition {
    final EasyCopyPage? page = _page;
    if (page == null) {
      return _currentUri;
    }
    return AppConfig.rewriteToCurrentHost(Uri.parse(page.uri));
  }

  String get _standardBodyTransitionScope =>
      standardPageTransitionScope(_page, _visiblePageUriForTransition);

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
}
