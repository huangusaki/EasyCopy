import 'package:flutter/material.dart';

class AppConfig {
  AppConfig._();

  static const String appName = 'EasyCopy';
  static const String appDescription =
      'Hide the original desktop page and render a mobile-first reading UI.';
  static const String baseUrl = 'https://www.2026copy.com/';
  static const Set<String> allowedHosts = <String>{
    'www.2026copy.com',
    '2026copy.com',
  };
  static const String desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static final Uri baseUri = Uri.parse(baseUrl);

  static Uri resolvePath(String path) {
    final String normalizedPath = path.startsWith('/')
        ? path.substring(1)
        : path;
    return baseUri.resolve(normalizedPath);
  }

  static Uri resolveNavigationUri(String href, {Uri? currentUri}) {
    final String trimmedHref = href.trim();
    if (trimmedHref.isEmpty) {
      return currentUri ?? baseUri;
    }

    final Uri? parsed = Uri.tryParse(trimmedHref);
    if (parsed != null && parsed.hasScheme) {
      return parsed;
    }

    return (currentUri ?? baseUri).resolve(trimmedHref);
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

  static bool isPrimaryDestination(Uri uri) {
    return appDestinations.any((AppDestination destination) {
      return destination.uri.path == uri.path &&
          destination.uri.query == uri.query;
    });
  }

  static bool isAllowedNavigationUri(Uri? uri) {
    if (uri == null || !uri.hasScheme) {
      return true;
    }

    if (uri.scheme == 'about' || uri.scheme == 'data') {
      return true;
    }

    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return false;
    }

    return allowedHosts.contains(uri.host);
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

const List<AppDestination> appDestinations = <AppDestination>[
  AppDestination(label: '首頁', icon: Icons.home, path: '/'),
  AppDestination(label: '發現', icon: Icons.explore, path: '/comics'),
  AppDestination(label: '排行', icon: Icons.bar_chart, path: '/rank'),
  AppDestination(
    label: '我的',
    icon: Icons.person,
    path: '/web/login?url=person/home',
  ),
];

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
