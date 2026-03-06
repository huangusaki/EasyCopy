import 'package:easy_copy/services/host_manager.dart';
import 'package:flutter/material.dart';

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

  static Uri rewriteToCurrentHost(Uri uri) => hostManager.rewriteToCurrentHost(uri);

  static Uri get profileUri => resolvePath(profilePath);

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

  static Uri buildSearchUri(String query) {
    final String normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      return resolvePath('/search');
    }
    return resolvePath(
      '/search?q=${Uri.encodeQueryComponent(normalizedQuery)}',
    );
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

  if (path.startsWith('/comics') ||
      path.startsWith('/comic') ||
      path.startsWith('/filter') ||
      path.startsWith('/search') ||
      path.startsWith('/topic') ||
      path.startsWith('/recommend') ||
      path.startsWith('/newest')) {
    return 1;
  }

  return 0;
}
