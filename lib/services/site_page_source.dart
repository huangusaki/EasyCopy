import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:reader/config/app_config.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/services/debug_trace.dart';
import 'package:reader/services/navigation_request_guard.dart';
import 'package:reader/services/network_diagnostics.dart';
import 'package:reader/services/site_api_client.dart';
import 'package:reader/services/site_html_page_loader.dart';

typedef SitePageLoader =
    Future<SitePage> Function(
      Uri uri, {
      required String authScope,
      NavigationRequestContext? requestContext,
    });

typedef ProfilePageLoader =
    Future<ProfilePageData> Function(Uri uri, {required String authScope});

typedef DesktopPageLoader = Future<SitePage> Function(Uri uri, {int? loadId});

/// A page source owns retrieval; cache and navigation lifetimes belong to callers.
abstract interface class SitePageSource {
  Future<SitePage> load(
    Uri uri, {
    required String authScope,
    NavigationRequestContext? requestContext,
  });
}

enum SitePageRoute {
  profile,
  search,
  reader,
  html,
  standard;

  static SitePageRoute forUri(Uri uri) {
    if (uri.path.startsWith(AppConfig.profilePath)) {
      return profile;
    }
    if (uri.path.startsWith('/search')) {
      return search;
    }
    final String path = uri.path.toLowerCase();
    if (path.contains('/chapter/')) {
      return reader;
    }
    if (path == '/' ||
        path.startsWith('/comics') ||
        path.startsWith('/filter') ||
        path.startsWith('/recommend') ||
        path.startsWith('/newest') ||
        path.startsWith('/author') ||
        path.startsWith('/rank') ||
        path.startsWith('/comic/')) {
      return html;
    }
    return standard;
  }
}

/// Shared by foreground navigation and chapter download preparation.
class PlatformHtmlPageSource implements SitePageSource {
  const PlatformHtmlPageSource({
    required SiteHtmlPageLoader htmlLoader,
    required DesktopPageLoader desktopLoader,
    required bool useDesktopWebView,
  }) : _htmlLoader = htmlLoader,
       _desktopLoader = desktopLoader,
       _useDesktopWebView = useDesktopWebView;

  final SiteHtmlPageLoader _htmlLoader;
  final DesktopPageLoader _desktopLoader;
  final bool _useDesktopWebView;

  @override
  Future<SitePage> load(
    Uri uri, {
    required String authScope,
    NavigationRequestContext? requestContext,
  }) {
    final Uri targetUri = AppConfig.rewriteToCurrentHost(uri);
    return _useDesktopWebView
        ? _desktopLoader(targetUri)
        : _htmlLoader.loadPage(targetUri, authScope: authScope);
  }
}

/// Keeps route selection and reader fallback independent of Flutter State.
class RoutedSitePageSource implements SitePageSource {
  const RoutedSitePageSource({
    required SiteApiClient apiClient,
    required ProfilePageLoader profileLoader,
    required SitePageLoader standardLoader,
    required SitePageSource htmlSource,
  }) : _apiClient = apiClient,
       _profileLoader = profileLoader,
       _standardLoader = standardLoader,
       _htmlSource = htmlSource;

  final SiteApiClient _apiClient;
  final ProfilePageLoader _profileLoader;
  final SitePageLoader _standardLoader;
  final SitePageSource _htmlSource;

  @override
  Future<SitePage> load(
    Uri uri, {
    required String authScope,
    NavigationRequestContext? requestContext,
  }) async {
    final Uri targetUri = AppConfig.rewriteToCurrentHost(uri);
    switch (SitePageRoute.forUri(targetUri)) {
      case SitePageRoute.profile:
        return _profileLoader(targetUri, authScope: authScope);
      case SitePageRoute.search:
        // SiteApiClient owns the Windows WebView2 / Android QUIC transport.
        return _apiClient.loadSearchResults(
          query: targetUri.queryParameters['q'] ?? '',
          page: int.tryParse(targetUri.queryParameters['page'] ?? '') ?? 1,
          qType: targetUri.queryParameters['q_type'] ?? '',
        );
      case SitePageRoute.reader:
        try {
          DebugTrace.log('reader.html_loader_start', <String, Object?>{
            'uri': targetUri.toString(),
          });
          final SitePage page = await _htmlSource.load(
            targetUri,
            authScope: authScope,
            requestContext: requestContext,
          );
          _probeReader(page, label: 'reader.first_image');
          return page;
        } catch (error) {
          DebugTrace.log('reader.html_loader_fallback', <String, Object?>{
            'uri': targetUri.toString(),
            'error': error.toString(),
          });
          debugPrint(
            'Reader HTML loader failed for ${targetUri.path}; '
            'falling back to standard loader. $error',
          );
          final SitePage page = await _standardLoader(
            targetUri,
            authScope: authScope,
            requestContext: requestContext,
          );
          _probeReader(page, label: 'reader.first_image_fallback');
          return page;
        }
      case SitePageRoute.html:
        return _htmlSource.load(
          targetUri,
          authScope: authScope,
          requestContext: requestContext,
        );
      case SitePageRoute.standard:
        return _standardLoader(
          targetUri,
          authScope: authScope,
          requestContext: requestContext,
        );
    }
  }

  void _probeReader(SitePage page, {required String label}) {
    if (page is ReaderPageData && page.imageUrls.isNotEmpty) {
      unawaited(
        NetworkDiagnostics.probeImageVariants(
          page.imageUrls.first,
          referer: page.uri,
          label: label,
        ),
      );
    }
  }
}
