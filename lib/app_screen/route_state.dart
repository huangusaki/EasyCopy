import 'package:reader/app_screen/route_utils.dart' as route_utils;
import 'package:reader/config/app_config.dart';
import 'package:reader/models/page_models.dart';

class AppRouteState {
  const AppRouteState({
    required this.page,
    required this.currentUri,
    required this.selectedIndex,
    required this.isAuthenticated,
    required this.discoverFilterExpanded,
  });

  final SitePage? page;
  final Uri currentUri;
  final int selectedIndex;
  final bool isAuthenticated;
  final bool discoverFilterExpanded;

  bool get isDetailRoute {
    if (page is DetailPageData) {
      return true;
    }
    return route_utils.isDetailCatalogUri(currentUri);
  }

  bool get shouldShowSearchBar {
    if (page is ProfilePageData ||
        page is DetailPageData ||
        route_utils.isProfileUri(currentUri)) {
      return false;
    }
    return !isDetailRoute;
  }

  bool get isPrimaryTabContent {
    if (shouldShowBackButton) {
      return false;
    }
    final SitePage? currentPage = page;
    return currentPage == null ||
        currentPage is HomePageData ||
        currentPage is DiscoverPageData ||
        currentPage is RankPageData ||
        currentPage is ProfilePageData;
  }

  bool get shouldShowHeaderCard =>
      !isPrimaryTabContent &&
      !isDetailRoute &&
      !isSecondaryProfileRoute &&
      !hideSecondaryDiscoverHeader;

  bool get hideSecondaryDiscoverHeader =>
      route_utils.hideSecondaryDiscoverHeader(currentUri);

  bool get shouldShowBackButton {
    final SitePage? currentPage = page;
    if (isSecondaryDiscoverRoute || isSecondaryProfileRoute) {
      return true;
    }
    if (currentPage is DetailPageData ||
        currentPage is UnknownPageData ||
        isDetailRoute) {
      return true;
    }
    if ((currentPage is DiscoverPageData || currentPage == null) &&
        currentUri.path == '/search') {
      return true;
    }
    return false;
  }

  bool get isSecondaryDiscoverRoute =>
      route_utils.isSecondaryDiscoverRoute(currentUri);

  bool get isSecondaryProfileRoute =>
      route_utils.isSecondaryProfileRoute(currentUri);

  String get pageTitle {
    if (route_utils.isProfileUri(currentUri)) {
      return AppConfig.profileSubviewTitle(
        AppConfig.profileSubviewForUri(currentUri),
      );
    }
    final SitePage? currentPage = page;
    if (currentPage == null) {
      if (isDetailRoute) {
        return '漫画详情';
      }
      return appDestinations[selectedIndex].label;
    }
    return currentPage.title;
  }

  bool isUserScopedDetailUri(Uri uri) {
    return isAuthenticated && route_utils.isDetailCatalogUri(uri);
  }

  List<LinkAction> visibleDiscoverThemeOptions(List<LinkAction> options) {
    return route_utils.visibleDiscoverThemeOptions(
      options,
      expanded: discoverFilterExpanded,
    );
  }
}
