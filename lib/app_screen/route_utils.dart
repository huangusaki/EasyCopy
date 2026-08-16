import 'package:reader/config/app_config.dart';
import 'package:reader/models/page_models.dart';

bool isLoginUri(Uri? uri) {
  if (uri == null) {
    return false;
  }
  return uri.path.startsWith('/web/login');
}

bool isProfileUri(Uri uri) {
  return uri.path.startsWith('/person/home');
}

bool isReaderChapterUri(Uri uri) {
  return uri.path.toLowerCase().contains('/chapter/');
}

bool isDetailCatalogUri(Uri uri) {
  final String path = uri.path.toLowerCase();
  return path.startsWith('/comic/') && !path.contains('/chapter/');
}

bool isPrimaryDiscoverUri(Uri uri) {
  final String path = uri.path.toLowerCase();
  return path.startsWith('/comics') ||
      path.startsWith('/filter') ||
      path.startsWith('/search');
}

bool isDiscoverUri(Uri uri) {
  final String path = uri.path.toLowerCase();
  return path.startsWith('/comics') ||
      path.startsWith('/filter') ||
      path.startsWith('/search') ||
      path.startsWith('/recommend') ||
      path.startsWith('/newest');
}

bool isSecondaryDiscoverRoute(Uri uri) {
  return isDiscoverUri(uri) && !isPrimaryDiscoverUri(uri);
}

bool isSecondaryProfileRoute(Uri uri) {
  return isProfileUri(uri) &&
      AppConfig.profileSubviewForUri(uri) != ProfileSubview.root;
}

/// 登录后若仍是本地占位页，则重新拉取账号数据。
bool profileNeedsAccountRefresh({
  required Uri uri,
  required SitePage? page,
  required bool isAuthenticated,
}) {
  if (!isAuthenticated || page is! ProfilePageData) {
    return false;
  }
  // 缓存页无需账号数据。
  if (AppConfig.profileSubviewForUri(uri) == ProfileSubview.cached) {
    return false;
  }
  return page.user == null;
}

bool hideSecondaryDiscoverHeader(Uri uri) {
  if (!isSecondaryDiscoverRoute(uri)) {
    return false;
  }
  final String path = uri.path.toLowerCase();
  return path.startsWith('/recommend') || path.startsWith('/newest');
}

bool isDiscoverMoreCategoryOption(LinkAction option) {
  return option.label.contains('查看全部分類') ||
      option.href.contains('/filter?point=');
}

List<LinkAction> visibleDiscoverThemeOptions(
  List<LinkAction> options, {
  required bool expanded,
}) {
  if (expanded || options.length <= 16) {
    return options;
  }
  const int previewCount = 15;
  final List<LinkAction> visible = options
      .take(previewCount)
      .toList(growable: true);
  final int activeIndex = options.indexWhere((LinkAction option) {
    return option.active;
  });
  if (activeIndex >= previewCount) {
    visible.removeLast();
    visible.add(options[activeIndex]);
  }
  return visible;
}
