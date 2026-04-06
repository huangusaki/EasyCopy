import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/services/host_manager.dart';
import 'package:flutter/material.dart';

enum ProfileSubview { root, collections, history, cached }

class AppConfig {
  AppConfig._();

  static const String appName = 'EasyCopy';
  static const String appDescription =
      'Hide the original desktop page and render a mobile-first reading UI.';
  static const String profilePath = '/person/home';
  static const String profileRouteKey = '__profile__';

  static HostManager get hostManager => HostManager.instance;

  static String get desktopUserAgent => defaultDesktopUserAgent;

  static Uri get baseUri => hostManager.baseUri;

  static Uri resolvePath(String path) => hostManager.resolvePath(path);

  static Uri resolveNavigationUri(String href, {Uri? currentUri}) {
    return hostManager.resolveNavigationUri(href, currentUri: currentUri);
  }

  static Uri rewriteToCurrentHost(Uri uri) =>
      hostManager.rewriteToCurrentHost(uri);

  static Uri get profileUri => buildProfileUri();

  static Uri buildProfileUri({
    ProfileSubview view = ProfileSubview.root,
    int page = 1,
  }) {
    final Uri uri = resolvePath(profilePath);
    final String? queryValue = _profileSubviewQueryValue(view);
    final int normalizedPage = page < 1 ? 1 : page;
    final Map<String, String> queryParameters = <String, String>{
      if (queryValue != null) 'view': queryValue,
      if (normalizedPage > 1 && view != ProfileSubview.root)
        'page': '$normalizedPage',
    };
    return uri.replace(
      queryParameters: queryParameters.isEmpty ? null : queryParameters,
    );
  }

  static ProfileSubview profileSubviewForUri(Uri uri) {
    final Uri normalizedUri = rewriteToCurrentHost(uri);
    if (!normalizedUri.path.startsWith(profilePath)) {
      return ProfileSubview.root;
    }
    switch (normalizedUri.queryParameters['view']?.trim().toLowerCase()) {
      case 'collections':
        return ProfileSubview.collections;
      case 'history':
        return ProfileSubview.history;
      case 'cached':
        return ProfileSubview.cached;
      default:
        return ProfileSubview.root;
    }
  }

  static String profileSubviewTitle(ProfileSubview view) {
    switch (view) {
      case ProfileSubview.root:
        return '我的';
      case ProfileSubview.collections:
        return '我的收藏';
      case ProfileSubview.history:
        return '浏览历史';
      case ProfileSubview.cached:
        return '已缓存漫画';
    }
  }

  static int profilePageForUri(Uri uri) {
    final Uri normalizedUri = rewriteToCurrentHost(uri);
    final int? parsed = int.tryParse(
      (normalizedUri.queryParameters['page'] ?? '').trim(),
    );
    if (parsed == null || parsed < 1) {
      return 1;
    }
    return parsed;
  }

  static List<AppDestination> buildDestinations() {
    return <AppDestination>[
      const AppDestination(label: '首頁', icon: Icons.home, path: '/'),
      const AppDestination(label: '發現', icon: Icons.explore, path: '/comics'),
      const AppDestination(label: '排行', icon: Icons.bar_chart, path: '/rank'),
      const AppDestination(label: '我的', icon: Icons.person, path: profilePath),
    ];
  }

  static bool isPrimaryDestination(Uri uri) {
    return buildDestinations().any((AppDestination destination) {
      return destination.uri.path == uri.path &&
          destination.uri.query == uri.query;
    });
  }

  static bool isAllowedNavigationUri(Uri? uri) {
    return hostManager.isAllowedNavigationUri(uri);
  }

  static Uri buildSearchUri(String query, {int page = 1, String qType = ''}) {
    final String normalizedQuery = query.trim();
    final int normalizedPage = page < 1 ? 1 : page;
    final String normalizedQueryType = qType.trim();
    if (normalizedQuery.isEmpty) {
      return resolvePath('/search');
    }
    return resolvePath('/search').replace(
      queryParameters: <String, String>{
        'q': normalizedQuery,
        if (normalizedPage > 1) 'page': '$normalizedPage',
        if (normalizedQueryType.isNotEmpty) 'q_type': normalizedQueryType,
      },
    );
  }

  static Uri buildPagedUri(Uri uri, {required int page}) {
    final Uri normalizedUri = rewriteToCurrentHost(uri);
    final int normalizedPage = page < 1 ? 1 : page;
    final Map<String, String> queryParameters = Map<String, String>.from(
      normalizedUri.queryParameters,
    );
    if (normalizedPage <= 1) {
      queryParameters.remove('page');
    } else {
      queryParameters['page'] = '$normalizedPage';
    }
    return _replaceSortedQuery(normalizedUri, queryParameters);
  }

  static Uri buildDiscoverPagerJumpUri(
    Uri uri, {
    required PagerData pager,
    required int page,
  }) {
    final Uri normalizedUri = rewriteToCurrentHost(uri);
    final int normalizedPage = page < 1 ? 1 : page;
    final int? offsetLimit = _discoverPagerLimit(normalizedUri, pager);
    if (offsetLimit == null || offsetLimit <= 0) {
      return buildPagedUri(normalizedUri, page: normalizedPage);
    }

    final Map<String, String> queryParameters = Map<String, String>.from(
      normalizedUri.queryParameters,
    );
    queryParameters.remove('page');
    queryParameters['limit'] = '$offsetLimit';
    final int offset = (normalizedPage - 1) * offsetLimit;
    if (offset <= 0) {
      queryParameters.remove('offset');
    } else {
      queryParameters['offset'] = '$offset';
    }
    return _replaceSortedQuery(normalizedUri, queryParameters);
  }

  static String routeKeyForUri(Uri uri) {
    final Map<String, String> sortedQuery = Map<String, String>.fromEntries(
      uri.queryParameters.entries.toList()
        ..sort((MapEntry<String, String> left, MapEntry<String, String> right) {
          return left.key.compareTo(right.key);
        }),
    );
    final Uri normalized = Uri(
      path: uri.path.isEmpty ? '/' : uri.path,
      queryParameters: sortedQuery.isEmpty ? null : sortedQuery,
    );
    return normalized.toString();
  }

  static String? _profileSubviewQueryValue(ProfileSubview view) {
    switch (view) {
      case ProfileSubview.root:
        return null;
      case ProfileSubview.collections:
        return 'collections';
      case ProfileSubview.history:
        return 'history';
      case ProfileSubview.cached:
        return 'cached';
    }
  }

  static Uri _replaceSortedQuery(Uri uri, Map<String, String> queryParameters) {
    final List<MapEntry<String, String>> sortedQuery =
        queryParameters.entries.toList(growable: false)..sort((
          MapEntry<String, String> left,
          MapEntry<String, String> right,
        ) {
          return left.key.compareTo(right.key);
        });
    return uri.replace(
      queryParameters: sortedQuery.isEmpty
          ? null
          : Map<String, String>.fromEntries(sortedQuery),
    );
  }

  static int? _discoverPagerLimit(Uri currentUri, PagerData pager) {
    final int? currentLimit = _parsePositiveInt(
      currentUri.queryParameters['limit'],
    );
    if (currentLimit != null) {
      return currentLimit;
    }
    for (final String href in <String>[pager.nextHref, pager.prevHref]) {
      final String trimmed = href.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final Uri resolved = resolveNavigationUri(
        trimmed,
        currentUri: currentUri,
      );
      final int? resolvedLimit = _parsePositiveInt(
        resolved.queryParameters['limit'],
      );
      if (resolvedLimit != null) {
        return resolvedLimit;
      }
      final int? resolvedOffset = _parsePositiveInt(
        resolved.queryParameters['offset'],
      );
      if (resolvedOffset != null && pager.currentPageNumber == 1) {
        return resolvedOffset;
      }
    }
    return null;
  }

  static int? _parsePositiveInt(String? value) {
    final int? parsed = int.tryParse((value ?? '').trim());
    if (parsed == null || parsed <= 0) {
      return null;
    }
    return parsed;
  }
}

class AppDestination {
  const AppDestination({
    required this.label,
    required this.icon,
    required this.path,
  });

  final String label;
  final IconData icon;
  final String path;

  Uri get uri => AppConfig.resolvePath(path);
}

List<AppDestination> get appDestinations => AppConfig.buildDestinations();

int tabIndexForUri(Uri? uri) {
  if (uri == null) {
    return 0;
  }

  final String path = uri.path.toLowerCase();
  if (path.startsWith('/rank')) {
    return 2;
  }

  if (path.startsWith('/web/login') || path.startsWith('/person')) {
    return 3;
  }

  if (path.startsWith('/topic')) {
    return 0;
  }

  if (path.startsWith('/comics') ||
      path.startsWith('/comic') ||
      path.startsWith('/filter') ||
      path.startsWith('/search') ||
      path.startsWith('/recommend') ||
      path.startsWith('/newest')) {
    return 1;
  }

  return 0;
}

int resolveNavigationTabIndex(Uri? uri, {int? sourceTabIndex}) {
  if (uri == null) {
    return 0;
  }

  final Uri normalizedUri = AppConfig.rewriteToCurrentHost(uri);
  final String path = normalizedUri.path.toLowerCase();
  if (sourceTabIndex != null) {
    final bool isReaderRoute = path.contains('/chapter/');
    final bool isDetailRoute =
        path.startsWith('/comic/') && !path.contains('/chapter/');
    if (isReaderRoute || isDetailRoute) {
      return sourceTabIndex;
    }
  }
  return tabIndexForUri(normalizedUri);
}
