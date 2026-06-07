import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:reader/config/app_config.dart';
import 'package:reader/models/chapter_comment.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/services/network_client.dart';
import 'package:reader/services/site_json_utils.dart';
import 'package:reader/services/site_session.dart';

part 'site_api_client/parsing.dart';

class SiteApiException implements Exception {
  SiteApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SiteLoginResult {
  const SiteLoginResult({required this.token, required this.cookies});

  final String token;
  final Map<String, String> cookies;

  String get cookieHeader => cookies.entries
      .where((MapEntry<String, String> entry) => entry.value.trim().isNotEmpty)
      .map((MapEntry<String, String> entry) => '${entry.key}=${entry.value}')
      .join('; ');
}

class _PagedProfileSection {
  const _PagedProfileSection({
    this.items = const <Map<String, Object?>>[],
    this.pager = const PagerData(),
    this.total = 0,
  });

  final List<Map<String, Object?>> items;
  final PagerData pager;
  final int total;
}

class SiteApiClient {
  SiteApiClient({http.Client? client, SiteSession? session})
    : _client = client ?? http.Client(),
      _session = session ?? SiteSession.instance;

  static final SiteApiClient instance = SiteApiClient();
  static const String _chapterCommentApiHost = 'api.mangacopy.com';

  final http.Client _client;
  final SiteSession _session;
  static const int _searchPageSize = 12;
  static const int _profilePageSize = 20;

  int get profilePageSize => _profilePageSize;

  Future<SiteLoginResult> login({
    required String username,
    required String password,
  }) async {
    final String normalizedUsername = username.trim();
    final String normalizedPassword = password.trim();
    if (normalizedUsername.isEmpty || normalizedPassword.isEmpty) {
      throw SiteApiException('请输入账号和密码。');
    }

    Object? lastError;
    for (final String path in const <String>[
      '/api/kb/web/login',
      '/api/v1/login',
    ]) {
      try {
        return await _loginWithPath(
          path,
          username: normalizedUsername,
          password: normalizedPassword,
        );
      } catch (error) {
        lastError = error;
      }
    }

    if (lastError is SiteApiException) {
      throw lastError;
    }
    throw SiteApiException('登录失败，请稍后重试。');
  }

  Future<ProfilePageData> loadProfile({Uri? uri}) async {
    await _session.ensureInitialized();
    final Uri targetUri = AppConfig.rewriteToCurrentHost(
      uri ?? AppConfig.profileUri,
    );
    final ProfileSubview activeSubview = AppConfig.profileSubviewForUri(
      targetUri,
    );
    final ProfileCollectionSort collectionSort = _serverCollectionSort(
      AppConfig.profileCollectionSortForUri(targetUri),
    );
    final int activePage = AppConfig.profilePageForUri(targetUri);
    if (!_session.isAuthenticated || (_session.token ?? '').isEmpty) {
      return ProfilePageData.loggedOut(uri: targetUri.toString());
    }

    final Future<Map<String, Object?>> userFuture = _getJson(
      '/api/v2/web/user/info',
    );
    final Future<_PagedProfileSection> collectionsFuture =
        activeSubview == ProfileSubview.history
        ? Future<_PagedProfileSection>.value(const _PagedProfileSection())
        : _getPagedListOrEmpty(
            const <String>['/api/v3/member/collect/comics'],
            view: ProfileSubview.collections,
            page: activeSubview == ProfileSubview.collections ? activePage : 1,
            collectionSort: collectionSort,
          );
    final Future<_PagedProfileSection> historyFuture =
        activeSubview == ProfileSubview.collections
        ? Future<_PagedProfileSection>.value(const _PagedProfileSection())
        : _getPagedListOrEmpty(
            const <String>['/api/kb/web/browses', '/api/v2/web/browses'],
            view: ProfileSubview.history,
            page: activeSubview == ProfileSubview.history ? activePage : 1,
          );

    final Map<String, Object?> userPayload = await userFuture;
    final _PagedProfileSection collectionsPayload = await collectionsFuture;
    final _PagedProfileSection historyPayload = await historyFuture;

    final ProfileUserData user = _parseUser(userPayload);
    await _session.bindUserId(user.userId);
    final List<ProfileLibraryItem> collections = _parseCollections(
      collectionsPayload.items,
      sort: collectionSort,
    );
    final List<ProfileHistoryItem> history = _parseHistory(
      historyPayload.items,
    );

    return ProfilePageData(
      title: '我的',
      uri: targetUri.toString(),
      isLoggedIn: true,
      user: user,
      collections: collections,
      history: history,
      collectionsPager: collectionsPayload.pager,
      historyPager: historyPayload.pager,
      collectionsTotal: collectionsPayload.total,
      historyTotal: historyPayload.total,
      continueReading: history.isEmpty ? null : history.first,
    );
  }

  Future<ProfileUserData> loadUserInfo() async {
    await _session.ensureInitialized();
    if (!_session.isAuthenticated || (_session.token ?? '').isEmpty) {
      throw SiteApiException('请先登录后再操作。');
    }
    final Map<String, Object?> payload = await _getJson(
      '/api/v2/web/user/info',
    );
    final ProfileUserData user = _parseUser(payload);
    await _session.bindUserId(user.userId);
    return user;
  }

  Future<(List<ProfileLibraryItem> items, int total)> loadCollectionsPage({
    int page = 1,
    ProfileCollectionSort sort = AppConfig.defaultProfileCollectionSort,
  }) async {
    await _session.ensureInitialized();
    if (!_session.isAuthenticated || (_session.token ?? '').isEmpty) {
      throw SiteApiException('请先登录后再操作。');
    }
    final ProfileCollectionSort serverSort = _serverCollectionSort(sort);
    final _PagedProfileSection payload = await _getPagedListOrEmpty(
      const <String>['/api/v3/member/collect/comics'],
      view: ProfileSubview.collections,
      page: page,
      collectionSort: serverSort,
    );
    return (_parseCollections(payload.items, sort: serverSort), payload.total);
  }

  Future<(List<ProfileHistoryItem> items, int total)> loadHistoryPage({
    int page = 1,
  }) async {
    await _session.ensureInitialized();
    if (!_session.isAuthenticated || (_session.token ?? '').isEmpty) {
      throw SiteApiException('请先登录后再操作。');
    }
    final _PagedProfileSection payload = await _getPagedListOrEmpty(
      const <String>['/api/kb/web/browses', '/api/v2/web/browses'],
      view: ProfileSubview.history,
      page: page,
    );
    return (_parseHistory(payload.items), payload.total);
  }

  Future<void> setComicCollection({
    required String comicId,
    required bool isCollected,
  }) async {
    await _session.ensureInitialized();
    if (!_session.isAuthenticated || (_session.token ?? '').isEmpty) {
      throw SiteApiException('请先登录后再操作收藏。');
    }

    final String normalizedComicId = comicId.trim();
    if (normalizedComicId.isEmpty) {
      throw SiteApiException('漫画收藏信息缺失，请刷新详情页后重试。');
    }

    final http.Response response = await NetworkClient.post(
      _client,
      AppConfig.resolvePath('/api/v2/web/collect'),
      headers: <String, String>{
        'Authorization': 'Token ${_session.token}',
        'Accept': 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': AppConfig.desktopUserAgent,
        'platform': '2',
        if (_session.cookieHeader.isNotEmpty) 'Cookie': _session.cookieHeader,
      },
      body: <String, String>{
        'comic_id': normalizedComicId,
        'is_collect': isCollected ? '1' : '0',
      },
      label: 'api.collect',
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw SiteApiException('登录已失效，请重新登录。');
    }

    final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw SiteApiException('收藏接口返回格式异常。');
    }
    final Map<String, Object?> payload = decoded.map(
      (Object? key, Object? value) => MapEntry(key.toString(), value),
    );
    final int code = (payload['code'] as num?)?.toInt() ?? response.statusCode;
    if (code != 200) {
      throw SiteApiException((payload['message'] as String?) ?? '收藏失败：$code');
    }
  }

  Future<ChapterCommentFeed> loadChapterComments({
    required String chapterId,
    int limit = 40,
    int offset = 0,
  }) async {
    final String normalizedChapterId = chapterId.trim();
    if (normalizedChapterId.isEmpty) {
      throw SiteApiException('章节评论信息缺失，请刷新后重试。');
    }

    await _session.ensureInitialized();
    final int normalizedLimit = limit.clamp(1, 120);
    final int normalizedOffset = offset < 0 ? 0 : offset;
    final (:payload, :statusCode) = await _getChapterCommentJson(
      '/api/v3/roasts',
      queryParameters: <String, String>{
        'chapter_id': normalizedChapterId,
        'limit': '$normalizedLimit',
        'offset': '$normalizedOffset',
        '_update': 'true',
      },
      malformedMessage: '章节评论返回格式异常。',
    );
    final int code = (payload['code'] as num?)?.toInt() ?? statusCode;
    if (code != 200) {
      throw SiteApiException((payload['message'] as String?) ?? '评论加载失败：$code');
    }

    final Map<String, Object?> results = asStringKeyMap(payload['results']);
    final List<ChapterComment> comments = _extractList(results)
        .map(_parseChapterComment)
        .where((ChapterComment comment) => comment.message.isNotEmpty)
        .toList(growable: false);
    return ChapterCommentFeed(
      total: pickInt(results, const <String>[
        'total',
        'count',
        'total_count',
      ], fallback: comments.length),
      comments: comments,
    );
  }

  Future<void> postChapterComment({
    required String chapterId,
    required String content,
  }) async {
    await _session.ensureInitialized();
    if (!_session.isAuthenticated || (_session.token ?? '').isEmpty) {
      throw SiteApiException('请先登录后再评论。');
    }

    final String normalizedChapterId = chapterId.trim();
    final String normalizedContent = content.trim();
    if (normalizedChapterId.isEmpty) {
      throw SiteApiException('章节评论信息缺失，请刷新后重试。');
    }
    if (normalizedContent.isEmpty) {
      throw SiteApiException('请输入评论内容。');
    }

    final (:payload, :statusCode) = await _postChapterCommentJson(
      '/api/v3/member/roast',
      headers: _buildRequestHeaders(
        includeAuth: true,
        contentType: 'application/x-www-form-urlencoded',
        includeSiteContext: true,
      ),
      body: <String, String>{
        'chapter_id': normalizedChapterId,
        'roast': normalizedContent,
        '_update': 'true',
      },
      malformedMessage: '评论接口返回格式异常。',
    );
    final int code = (payload['code'] as num?)?.toInt() ?? statusCode;
    if (code != 200) {
      throw SiteApiException((payload['message'] as String?) ?? '评论发送失败：$code');
    }
  }

  Future<DiscoverPageData> loadSearchResults({
    required String query,
    int page = 1,
    String qType = '',
  }) async {
    final String normalizedQuery = query.trim();
    final int normalizedPage = page < 1 ? 1 : page;
    final String normalizedQueryType = qType.trim();
    if (normalizedQuery.isEmpty) {
      return DiscoverPageData(
        title: '搜索',
        uri: AppConfig.buildSearchUri('', page: normalizedPage).toString(),
        filters: const <FilterGroupData>[],
        items: const <ComicCardData>[],
        pager: const PagerData(),
        spotlight: const <ComicCardData>[],
      );
    }

    final Map<String, Object?> payload = await _getSearchJson(
      query: normalizedQuery,
      page: normalizedPage,
      qType: normalizedQueryType,
    );
    final Map<String, Object?> results = asStringKeyMap(payload['results']);
    final List<Map<String, Object?>> list = _extractList(results);
    final int total =
        (results['total'] as num?)?.toInt() ??
        (results['count'] as num?)?.toInt() ??
        (results['total_count'] as num?)?.toInt() ??
        list.length;
    final int totalPages = total <= 0
        ? 1
        : (total / _searchPageSize).ceil().clamp(1, 999999);

    return DiscoverPageData(
      title: '搜索',
      uri: AppConfig.buildSearchUri(
        normalizedQuery,
        page: normalizedPage,
        qType: normalizedQueryType,
      ).toString(),
      filters: const <FilterGroupData>[],
      items: list
          .map((Map<String, Object?> item) => _parseSearchComic(item))
          .where((ComicCardData item) => item.title.isNotEmpty)
          .toList(growable: false),
      pager: PagerData(
        currentLabel: '$normalizedPage',
        totalLabel: '共$totalPages页 · $total条',
        prevHref: normalizedPage > 1
            ? AppConfig.buildSearchUri(
                normalizedQuery,
                page: normalizedPage - 1,
                qType: normalizedQueryType,
              ).toString()
            : '',
        nextHref: normalizedPage < totalPages
            ? AppConfig.buildSearchUri(
                normalizedQuery,
                page: normalizedPage + 1,
                qType: normalizedQueryType,
              ).toString()
            : '',
      ),
      spotlight: const <ComicCardData>[],
    );
  }

  Future<Map<String, Object?>> _getJson(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    await _session.ensureInitialized();
    final Uri baseUri = AppConfig.resolvePath(path);
    final Uri uri = queryParameters == null || queryParameters.isEmpty
        ? baseUri
        : baseUri.replace(
            queryParameters: <String, String>{
              ...baseUri.queryParameters,
              ...queryParameters,
            },
          );
    final http.Response response = await NetworkClient.get(
      _client,
      uri,
      headers: <String, String>{
        'Authorization': 'Token ${_session.token}',
        'Accept': 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': AppConfig.desktopUserAgent,
        'platform': '2',
        if (_session.cookieHeader.isNotEmpty) 'Cookie': _session.cookieHeader,
      },
      label: 'api.json',
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw SiteApiException('登录已失效，请重新登录。');
    }
    final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw SiteApiException('接口返回格式异常。');
    }
    final Map<String, Object?> payload = decoded.map(
      (Object? key, Object? value) => MapEntry(key.toString(), value),
    );
    final int code = (payload['code'] as num?)?.toInt() ?? response.statusCode;
    if (code != 200) {
      throw SiteApiException((payload['message'] as String?) ?? '接口请求失败：$code');
    }
    return payload;
  }

  Future<({Map<String, Object?> payload, int statusCode})>
  _getChapterCommentJson(
    String path, {
    required Map<String, String> queryParameters,
    required String malformedMessage,
  }) async {
    await _session.ensureInitialized();
    Object? lastError;
    for (final String host in _chapterCommentApiHosts()) {
      final Uri uri = Uri.https(host, path, queryParameters);
      try {
        final http.Response response = await NetworkClient.get(
          _client,
          uri,
          headers: _buildRequestHeaders(includeSiteContext: true),
          maxRetries: 0,
          label: 'api.comments',
        );
        final Map<String, Object?>? payload = _tryDecodeJsonMap(response);
        if (payload == null) {
          lastError = SiteApiException(malformedMessage);
          continue;
        }
        return (payload: payload, statusCode: response.statusCode);
      } catch (error) {
        lastError = error;
      }
    }

    if (lastError is SiteApiException) {
      throw lastError;
    }
    throw SiteApiException('评论加载失败，请稍后重试。');
  }

  Future<({Map<String, Object?> payload, int statusCode})>
  _postChapterCommentJson(
    String path, {
    required Map<String, String> headers,
    required Object body,
    required String malformedMessage,
  }) async {
    await _session.ensureInitialized();
    Object? lastError;
    for (final String host in _chapterCommentApiHosts()) {
      final Uri uri = Uri.https(host, path);
      try {
        final http.Response response = await NetworkClient.post(
          _client,
          uri,
          headers: headers,
          body: body,
          label: 'api.comment.submit',
        );
        if (response.statusCode == 401 || response.statusCode == 403) {
          throw SiteApiException('登录已失效，请重新登录。');
        }
        final Map<String, Object?>? payload = _tryDecodeJsonMap(response);
        if (payload == null) {
          lastError = SiteApiException(malformedMessage);
          continue;
        }
        return (payload: payload, statusCode: response.statusCode);
      } on SiteApiException {
        rethrow;
      } catch (error) {
        lastError = error;
      }
    }

    if (lastError is SiteApiException) {
      throw lastError;
    }
    throw SiteApiException('评论发送失败，请稍后重试。');
  }

  Future<Map<String, Object?>> _getSearchJson({
    required String query,
    required int page,
    required String qType,
  }) async {
    await _session.ensureInitialized();
    final int offset = (page - 1) * _searchPageSize;
    Object? lastError;
    for (final String path in const <String>[
      '/api/kb/web/searchci/comics',
      '/api/kb/web/searchch/comics',
    ]) {
      try {
        final Uri uri = AppConfig.resolvePath(path).replace(
          queryParameters: <String, String>{
            'offset': '$offset',
            'platform': '2',
            'limit': '$_searchPageSize',
            'q': query,
            'q_type': qType,
          },
        );
        final http.Response response = await NetworkClient.get(
          _client,
          uri,
          headers: <String, String>{
            'Accept': 'application/json',
            'User-Agent': AppConfig.desktopUserAgent,
            'platform': '2',
            if (_session.cookieHeader.isNotEmpty)
              'Cookie': _session.cookieHeader,
          },
          label: 'api.search',
        );
        final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is! Map) {
          throw SiteApiException('搜索接口返回格式异常。');
        }
        final Map<String, Object?> payload = decoded.map(
          (Object? key, Object? value) => MapEntry(key.toString(), value),
        );
        final int code =
            (payload['code'] as num?)?.toInt() ?? response.statusCode;
        if (code != 200) {
          throw SiteApiException(
            (payload['message'] as String?) ?? '搜索失败：$code',
          );
        }
        return payload;
      } catch (error) {
        lastError = error;
      }
    }

    if (lastError is SiteApiException) {
      throw lastError;
    }
    throw SiteApiException('搜索失败，请稍后重试。');
  }

  Future<SiteLoginResult> _loginWithPath(
    String path, {
    required String username,
    required String password,
  }) async {
    final int salt = 100000 + Random().nextInt(900000);
    final Uri uri = AppConfig.resolvePath(path);
    final http.Response response = await NetworkClient.post(
      _client,
      uri,
      headers: <String, String>{
        'Accept': 'application/json, text/plain, */*',
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'User-Agent': AppConfig.desktopUserAgent,
        'platform': '2',
      },
      body: <String, String>{
        'username': username,
        'password': base64Encode(utf8.encode('$password-$salt')),
        'salt': '$salt',
        'platform': '2',
        'version': '2025.12.10',
        'source': 'freeSite',
      },
      label: 'api.login',
    );

    final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw SiteApiException('登录返回格式异常。');
    }
    final Map<String, Object?> payload = decoded.map(
      (Object? key, Object? value) => MapEntry(key.toString(), value),
    );
    final int code = (payload['code'] as num?)?.toInt() ?? response.statusCode;
    if (code != 200) {
      throw SiteApiException((payload['message'] as String?) ?? '登录失败：$code');
    }

    final Map<String, Object?> results = asStringKeyMap(payload['results']);
    final String token = pickString(results, <String>['token']);
    if (token.isEmpty) {
      throw SiteApiException('登录成功，但未拿到有效凭证。');
    }

    return SiteLoginResult(
      token: token,
      cookies: <String, String>{
        'token': token,
        if (pickString(results, <String>['username']).isNotEmpty)
          'name': pickString(results, <String>['username']),
        if (pickString(results, <String>['user_id']).isNotEmpty)
          'user_id': pickString(results, <String>['user_id']),
        if (pickString(results, <String>['avatar']).isNotEmpty)
          'avatar': pickString(results, <String>['avatar']),
        if (pickString(results, <String>['datetime_created']).isNotEmpty)
          'create': pickString(results, <String>['datetime_created']),
      },
    );
  }

  Future<_PagedProfileSection> _getPagedListOrEmpty(
    List<String> paths, {
    required ProfileSubview view,
    required int page,
    ProfileCollectionSort collectionSort =
        AppConfig.defaultProfileCollectionSort,
  }) async {
    Object? lastError;
    for (final String path in paths) {
      try {
        return await _getPagedList(
          path,
          view: view,
          page: page,
          collectionSort: collectionSort,
        );
      } catch (error) {
        lastError = error;
      }
    }
    if (lastError is SiteApiException && lastError.message.contains('登录已失效')) {
      throw lastError;
    }
    return _emptyPagedSection(
      view: view,
      page: page,
      collectionSort: collectionSort,
    );
  }

  Future<_PagedProfileSection> _getPagedList(
    String path, {
    required ProfileSubview view,
    required int page,
    ProfileCollectionSort collectionSort =
        AppConfig.defaultProfileCollectionSort,
  }) async {
    final int normalizedPage = page < 1 ? 1 : page;
    final int offset = (normalizedPage - 1) * _profilePageSize;
    final Map<String, String> queryParameters = <String, String>{
      'offset': '$offset',
      'limit': '$_profilePageSize',
    };
    if (view == ProfileSubview.collections) {
      queryParameters.addAll(<String, String>{
        'free_type': '1',
        'ordering': _collectionOrdering(collectionSort),
      });
    }
    final Map<String, Object?> payload = await _getJson(
      path,
      queryParameters: queryParameters,
    );
    final Map<String, Object?> results = asStringKeyMap(payload['results']);
    final List<Map<String, Object?>> items = <Map<String, Object?>>[
      ..._extractList(results),
    ];
    final int total = pickInt(results, const <String>[
      'total',
      'count',
      'total_count',
    ], fallback: items.length);
    final int limit = pickInt(results, const <String>[
      'limit',
      'page_size',
      'pageSize',
    ], fallback: _profilePageSize);
    final int effectiveLimit = limit <= 0 ? _profilePageSize : limit;
    final int totalPages = total <= 0
        ? 1
        : ((total + effectiveLimit - 1) / effectiveLimit).floor();
    final int clampedPage = normalizedPage > totalPages
        ? totalPages
        : normalizedPage;
    return _PagedProfileSection(
      items: items,
      total: total,
      pager: _buildProfilePager(
        view: view,
        currentPage: clampedPage,
        totalPages: totalPages,
        totalItems: total,
        collectionSort: collectionSort,
      ),
    );
  }

  _PagedProfileSection _emptyPagedSection({
    required ProfileSubview view,
    required int page,
    ProfileCollectionSort collectionSort =
        AppConfig.defaultProfileCollectionSort,
  }) {
    final int normalizedPage = page < 1 ? 1 : page;
    return _PagedProfileSection(
      pager: _buildProfilePager(
        view: view,
        currentPage: normalizedPage,
        totalPages: 1,
        totalItems: 0,
        collectionSort: collectionSort,
      ),
    );
  }

  PagerData _buildProfilePager({
    required ProfileSubview view,
    required int currentPage,
    required int totalPages,
    required int totalItems,
    ProfileCollectionSort collectionSort =
        AppConfig.defaultProfileCollectionSort,
  }) {
    final int normalizedCurrentPage = currentPage < 1 ? 1 : currentPage;
    final int normalizedTotalPages = totalPages < 1 ? 1 : totalPages;
    final String itemUnit = switch (view) {
      ProfileSubview.collections => '部',
      ProfileSubview.history => '条',
      _ => '条',
    };
    return PagerData(
      currentLabel: '$normalizedCurrentPage',
      totalLabel: '共$normalizedTotalPages页 · $totalItems$itemUnit',
      prevHref: normalizedCurrentPage > 1
          ? AppConfig.buildProfileUri(
              view: view,
              page: normalizedCurrentPage - 1,
              collectionSort: view == ProfileSubview.collections
                  ? collectionSort
                  : null,
            ).toString()
          : '',
      nextHref: normalizedCurrentPage < normalizedTotalPages
          ? AppConfig.buildProfileUri(
              view: view,
              page: normalizedCurrentPage + 1,
              collectionSort: view == ProfileSubview.collections
                  ? collectionSort
                  : null,
            ).toString()
          : '',
    );
  }

  Map<String, String> _buildRequestHeaders({
    bool includeAuth = false,
    String accept = 'application/json',
    String? contentType,
    bool includeSiteContext = false,
  }) {
    final Uri siteBaseUri = AppConfig.baseUri;
    return <String, String>{
      'Accept': accept,
      if (contentType != null) 'Content-Type': contentType,
      'User-Agent': AppConfig.desktopUserAgent,
      'platform': '2',
      if (includeSiteContext) 'Origin': siteBaseUri.origin,
      if (includeSiteContext) 'Referer': siteBaseUri.toString(),
      if (includeAuth && (_session.token ?? '').isNotEmpty)
        'Authorization': 'Token ${_session.token}',
      if (_session.cookieHeader.isNotEmpty) 'Cookie': _session.cookieHeader,
    };
  }

  List<String> _chapterCommentApiHosts() {
    final String currentHost = AppConfig.baseUri.host.trim().toLowerCase();
    final String bareHost = currentHost.startsWith('www.')
        ? currentHost.substring(4)
        : currentHost;
    final List<String> candidates = <String>[
      if (bareHost.isNotEmpty) 'api.$bareHost',
      _chapterCommentApiHost,
      'api.copy-manga.com',
      'api.2026copy.com',
    ];
    final Set<String> seen = <String>{};
    return candidates
        .where((String host) => host.trim().isNotEmpty)
        .where((String host) => seen.add(host))
        .toList(growable: false);
  }

  Map<String, Object?>? _tryDecodeJsonMap(http.Response response) {
    try {
      final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) {
        return null;
      }
      return decoded.map(
        (Object? key, Object? value) => MapEntry(key.toString(), value),
      );
    } catch (_) {
      return null;
    }
  }

  String _collectionOrdering(ProfileCollectionSort sort) {
    return switch (sort) {
      ProfileCollectionSort.readingTime => '-datetime_browse',
      ProfileCollectionSort.latestUpdate => '-datetime_updated',
      ProfileCollectionSort.alphabetical => '-datetime_updated',
    };
  }

  ProfileCollectionSort _serverCollectionSort(ProfileCollectionSort sort) {
    return sort == ProfileCollectionSort.alphabetical
        ? AppConfig.defaultProfileCollectionSort
        : sort;
  }

  int _compareByUpdatedDesc(ProfileLibraryItem left, ProfileLibraryItem right) {
    final DateTime? leftUpdatedAt = _tryParseSortDateTime(left.updatedAt);
    final DateTime? rightUpdatedAt = _tryParseSortDateTime(right.updatedAt);
    if (leftUpdatedAt != null && rightUpdatedAt != null) {
      final int dateCompare = rightUpdatedAt.compareTo(leftUpdatedAt);
      if (dateCompare != 0) {
        return dateCompare;
      }
    } else if (leftUpdatedAt != null) {
      return -1;
    } else if (rightUpdatedAt != null) {
      return 1;
    }
    final int textCompare = right.updatedAt.compareTo(left.updatedAt);
    if (textCompare != 0) {
      return textCompare;
    }
    return left.title.compareTo(right.title);
  }

  DateTime? _tryParseSortDateTime(String value) {
    final String normalized = value.trim();
    if (normalized.isEmpty) {
      return null;
    }
    final List<String> candidates = <String>{
      normalized,
      normalized.replaceAll('/', '-'),
      normalized.replaceFirst(' ', 'T'),
      normalized.replaceAll('/', '-').replaceFirst(' ', 'T'),
    }.toList(growable: false);
    for (final String candidate in candidates) {
      final DateTime? parsed = DateTime.tryParse(candidate);
      if (parsed != null) {
        return parsed;
      }
    }
    return null;
  }
}
