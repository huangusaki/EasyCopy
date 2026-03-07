import 'package:easy_copy/config/app_config.dart';
import 'package:easy_copy/models/page_models.dart';

String standardPageTransitionScope(EasyCopyPage? page, Uri uri) {
  final Uri normalizedUri = AppConfig.rewriteToCurrentHost(uri);
  final String routeKey = AppConfig.routeKeyForUri(normalizedUri);

  if (page is DiscoverPageData) {
    if (normalizedUri.path == '/search') {
      return 'search::$routeKey';
    }
    return 'discover';
  }
  if (page is RankPageData) {
    return 'rank';
  }
  if (page is DetailPageData || _isDetailUri(normalizedUri)) {
    return 'detail::$routeKey';
  }
  if (page is ProfilePageData ||
      normalizedUri.path.startsWith(AppConfig.profilePath)) {
    return 'profile::$routeKey';
  }
  if (page is UnknownPageData) {
    return 'unknown::$routeKey';
  }
  if (page is HomePageData || normalizedUri.path == '/') {
    return 'home';
  }
  if (normalizedUri.path == '/search') {
    return 'search::$routeKey';
  }
  if (normalizedUri.path.startsWith('/rank')) {
    return 'rank';
  }
  if (normalizedUri.path.startsWith('/comics') ||
      normalizedUri.path.startsWith('/filter') ||
      normalizedUri.path.startsWith('/topic') ||
      normalizedUri.path.startsWith('/recommend') ||
      normalizedUri.path.startsWith('/newest')) {
    return 'discover';
  }
  return 'route::$routeKey';
}

bool _isDetailUri(Uri uri) {
  final String path = uri.path.toLowerCase();
  return path.startsWith('/comic/') && !path.contains('/chapter/');
}
