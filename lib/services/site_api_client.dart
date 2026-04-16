import 'dart:convert';
import 'dart:math';

import 'package:easy_copy/config/app_config.dart';
import 'package:easy_copy/models/chapter_comment.dart';
import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/services/site_session.dart';
import 'package:http/http.dart' as http;

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
    final Map<String, Object?> payload = await _getJson('/api/v2/web/user/info');
    final ProfileUserData user = _parseUser(payload);
    await _session.bindUserId(user.userId);
    return user;
  }

  Future<(List<ProfileLibraryItem> items, int total)> loadCollectionsPage({
    int page = 1,
  }) async {
    await _session.ensureInitialized();
    if (!_session.isAuthenticated || (_session.token ?? '').isEmpty) {
      throw SiteApiException('请先登录后再操作。');
    }
    final _PagedProfileSection payload = await _getPagedListOrEmpty(
      const <String>['/api/v3/member/collect/comics'],
      view: ProfileSubview.collections,
      page: page,
    );
    return (_parseCollections(payload.items), payload.total);
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

    final http.Response response = await _client.post(
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
    final Uri uri = Uri.https(_chapterCommentApiHost, '/api/v3/roasts', <String, String>{
      'chapter_id': normalizedChapterId,
      'limit': '$normalizedLimit',
      'offset': '$normalizedOffset',
      '_update': 'true',
    });
    final http.Response response = await _client.get(
      uri,
      headers: _buildRequestHeaders(),
    );
    final Map<String, Object?> payload = _decodeJsonMap(
      response,
      malformedMessage: '章节评论返回格式异常。',
    );
    final int code = (payload['code'] as num?)?.toInt() ?? response.statusCode;
    if (code != 200) {
      throw SiteApiException((payload['message'] as String?) ?? '评论加载失败：$code');
    }

    final Map<String, Object?> results = _asMap(payload['results']);
    final List<ChapterComment> comments = _extractList(results)
        .map(_parseChapterComment)
        .where((ChapterComment comment) => comment.message.isNotEmpty)
        .toList(growable: false);
    return ChapterCommentFeed(
      total: _pickInt(
        results,
        const <String>['total', 'count', 'total_count'],
        fallback: comments.length,
      ),
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

    final http.Response response = await _client.post(
      Uri.https(_chapterCommentApiHost, '/api/v3/member/roast'),
      headers: _buildRequestHeaders(
        includeAuth: true,
        contentType: 'application/x-www-form-urlencoded',
      ),
      body: <String, String>{
        'chapter_id': normalizedChapterId,
        'roast': normalizedContent,
        '_update': 'true',
      },
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw SiteApiException('登录已失效，请重新登录。');
    }

    final Map<String, Object?> payload = _decodeJsonMap(
      response,
      malformedMessage: '评论接口返回格式异常。',
    );
    final int code = (payload['code'] as num?)?.toInt() ?? response.statusCode;
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
    final Map<String, Object?> results = _asMap(payload['results']);
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
    final http.Response response = await _client.get(
      uri,
      headers: <String, String>{
        'Authorization': 'Token ${_session.token}',
        'Accept': 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': AppConfig.desktopUserAgent,
        'platform': '2',
        if (_session.cookieHeader.isNotEmpty) 'Cookie': _session.cookieHeader,
      },
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
        final http.Response response = await _client.get(
          uri,
          headers: <String, String>{
            'Accept': 'application/json',
            'User-Agent': AppConfig.desktopUserAgent,
            'platform': '2',
            if (_session.cookieHeader.isNotEmpty) 'Cookie': _session.cookieHeader,
          },
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
    final http.Response response = await _client.post(
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

    final Map<String, Object?> results = _asMap(payload['results']);
    final String token = _pickString(results, <String>['token']);
    if (token.isEmpty) {
      throw SiteApiException('登录成功，但未拿到有效凭证。');
    }

    return SiteLoginResult(
      token: token,
      cookies: <String, String>{
        'token': token,
        if (_pickString(results, <String>['username']).isNotEmpty)
          'name': _pickString(results, <String>['username']),
        if (_pickString(results, <String>['user_id']).isNotEmpty)
          'user_id': _pickString(results, <String>['user_id']),
        if (_pickString(results, <String>['avatar']).isNotEmpty)
          'avatar': _pickString(results, <String>['avatar']),
        if (_pickString(results, <String>['datetime_created']).isNotEmpty)
          'create': _pickString(results, <String>['datetime_created']),
      },
    );
  }

  Future<_PagedProfileSection> _getPagedListOrEmpty(
    List<String> paths, {
    required ProfileSubview view,
    required int page,
  }) async {
    Object? lastError;
    for (final String path in paths) {
      try {
        return await _getPagedList(path, view: view, page: page);
      } catch (error) {
        lastError = error;
      }
    }
    if (lastError is SiteApiException && lastError.message.contains('登录已失效')) {
      throw lastError;
    }
    return _emptyPagedSection(view: view, page: page);
  }

  Future<_PagedProfileSection> _getPagedList(
    String path, {
    required ProfileSubview view,
    required int page,
  }) async {
    final int normalizedPage = page < 1 ? 1 : page;
    final int offset = (normalizedPage - 1) * _profilePageSize;
    final Map<String, String> queryParameters = <String, String>{
      'offset': '$offset',
      'limit': '$_profilePageSize',
    };
    if (view == ProfileSubview.collections) {
      queryParameters.addAll(const <String, String>{
        'free_type': '1',
        'ordering': '-datetime_updated',
      });
    }
    final Map<String, Object?> payload = await _getJson(
      path,
      queryParameters: queryParameters,
    );
    final Map<String, Object?> results = _asMap(payload['results']);
    final List<Map<String, Object?>> items = <Map<String, Object?>>[
      ..._extractList(results),
    ];
    final int total = _pickInt(results, const <String>[
      'total',
      'count',
      'total_count',
    ], fallback: items.length);
    final int limit = _pickInt(results, const <String>[
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
      ),
    );
  }

  _PagedProfileSection _emptyPagedSection({
    required ProfileSubview view,
    required int page,
  }) {
    final int normalizedPage = page < 1 ? 1 : page;
    return _PagedProfileSection(
      pager: _buildProfilePager(
        view: view,
        currentPage: normalizedPage,
        totalPages: 1,
        totalItems: 0,
      ),
    );
  }

  PagerData _buildProfilePager({
    required ProfileSubview view,
    required int currentPage,
    required int totalPages,
    required int totalItems,
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
            ).toString()
          : '',
      nextHref: normalizedCurrentPage < normalizedTotalPages
          ? AppConfig.buildProfileUri(
              view: view,
              page: normalizedCurrentPage + 1,
            ).toString()
          : '',
    );
  }

  ProfileUserData _parseUser(Map<String, Object?> payload) {
    final Map<String, Object?> results = _asMap(payload['results']);
    final String userId = _pickString(results, <String>[
      'user_id',
      'id',
      'uuid',
    ]);
    final String username = _pickString(results, <String>[
      'username',
      'mobile',
      'email',
    ]);
    final String nickname = _pickString(results, <String>['nickname', 'name']);
    final String avatarUrl = _pickString(results, <String>[
      'avatar',
      'avatar_url',
    ]);
    final String createdAt = _pickString(results, <String>[
      'createDate',
      'datetime_created',
      'created_at',
    ]);
    final List<String> memberships = <String>[
      if (_pickBool(results, 'vip')) 'VIP',
      if (_pickBool(results, 'comic_vip')) '漫畫會員',
      if (_pickBool(results, 'cartoon_vip')) '動畫會員',
    ];
    return ProfileUserData(
      userId: userId,
      username: username.isEmpty ? '未命名用戶' : username,
      nickname: nickname,
      avatarUrl: avatarUrl,
      createdAt: createdAt,
      membershipLabel: memberships.isEmpty ? '普通會員' : memberships.join(' / '),
    );
  }

  List<ProfileLibraryItem> _parseCollections(Object? results) {
    final List<ProfileLibraryItem> items = _extractList(results)
        .map((Map<String, Object?> item) {
          final Map<String, Object?> comic = _firstNonEmptyMap(item, <String>[
            'comic',
            'comic_info',
            'cartoon',
            'results',
          ]);
          final Map<String, Object?> source = comic.isEmpty ? item : comic;
          final String pathWord = _pickString(source, <String>[
            'path_word',
            'pathWord',
            'slug',
          ]);
          final String updatedAt =
              _pickString(source, <String>[
                'datetime_updated',
                'updated_at',
                'updatedAt',
                'last_update_time',
                'last_update_at',
                'update_time',
              ]).isNotEmpty
              ? _pickString(source, <String>[
                  'datetime_updated',
                  'updated_at',
                  'updatedAt',
                  'last_update_time',
                  'last_update_at',
                  'update_time',
                ])
              : _pickString(item, <String>[
                  'datetime_updated',
                  'updated_at',
                  'updatedAt',
                  'last_update_time',
                  'last_update_at',
                  'update_time',
                ]);
          return ProfileLibraryItem(
            title: _pickString(source, <String>['name', 'title']),
            coverUrl: _pickString(source, <String>[
              'cover',
              'cover_url',
              'image',
            ]),
            href: _buildComicHref(pathWord, source, item),
            subtitle: _pickString(source, <String>[
              'author_name',
              'author',
              'subtitle',
            ]),
            secondaryText: _pickString(source, <String>[
              'last_chapter_name',
              'datetime_updated',
              'status',
            ]),
            updatedAt: updatedAt,
          );
        })
        .where((ProfileLibraryItem item) => item.title.isNotEmpty)
        .toList(growable: false);
    items.sort(_compareProfileLibraryItemByUpdatedAtDesc);
    return items;
  }

  List<ProfileHistoryItem> _parseHistory(Object? results) {
    return _extractList(results)
        .map((Map<String, Object?> item) {
          final Map<String, Object?> comic = _firstNonEmptyMap(item, <String>[
            'comic',
            'comic_info',
            'cartoon',
          ]);
          final Map<String, Object?> chapter = _firstNonEmptyMap(item, <String>[
            'chapter',
            'last_chapter',
            'browse',
          ]);
          final Map<String, Object?> source = comic.isEmpty ? item : comic;
          final String pathWord = _pickString(source, <String>[
            'path_word',
            'pathWord',
            'slug',
          ]);
          final String chapterUuid =
              _pickString(chapter, <String>[
                'uuid',
                'chapter_uuid',
                'id',
              ]).isNotEmpty
              ? _pickString(chapter, <String>['uuid', 'chapter_uuid', 'id'])
              : _pickString(item, <String>['last_chapter_id']);
          final String chapterLabel =
              _pickString(chapter, <String>[
                'name',
                'title',
                'chapter_name',
              ]).isNotEmpty
              ? _pickString(chapter, <String>['name', 'title', 'chapter_name'])
              : _pickString(item, <String>['last_chapter_name']);
          return ProfileHistoryItem(
            title: _pickString(source, <String>['name', 'title']),
            coverUrl: _pickString(source, <String>[
              'cover',
              'cover_url',
              'image',
            ]),
            comicHref: _buildComicHref(pathWord, source, item),
            chapterLabel: chapterLabel,
            chapterHref: _buildChapterHref(pathWord, chapterUuid),
            visitedAt: _pickString(item, <String>[
              'datetime_created',
              'datetime_updated',
              'created_at',
            ]),
          );
        })
        .where((ProfileHistoryItem item) => item.title.isNotEmpty)
        .toList(growable: false);
  }

  ComicCardData _parseSearchComic(Map<String, Object?> item) {
    final Map<String, Object?> source =
        _firstNonEmptyMap(item, <String>[
          'comic',
          'comic_info',
          'cartoon',
          'results',
        ]).isNotEmpty
        ? _firstNonEmptyMap(item, <String>[
            'comic',
            'comic_info',
            'cartoon',
            'results',
          ])
        : item;
    final String pathWord = _pickString(source, <String>[
      'path_word',
      'pathWord',
      'slug',
    ]);
    final String authorText = _searchAuthorLabel(source);
    return ComicCardData(
      title: _pickString(source, <String>['name', 'title']),
      subtitle: authorText.isEmpty ? '作者：--' : '作者：$authorText',
      secondaryText: _pickString(source, <String>[
        'datetime_updated',
        'status',
        'brief',
      ]),
      coverUrl: _pickString(source, <String>['cover', 'cover_url', 'image']),
      href: _buildComicHref(pathWord, source, item),
    );
  }

  ChapterComment _parseChapterComment(Map<String, Object?> item) {
    final Map<String, Object?> user = _firstNonEmptyMap(
      item,
      const <String>['user', 'member', 'author'],
    );
    final int commentId = _pickInt(item, const <String>['id'], fallback: 0);
    return ChapterComment(
      id: commentId > 0
          ? '$commentId'
          : _pickString(item, const <String>['uuid', 'comment_id', 'roast_id']),
      message: _pickString(
        item,
        const <String>['comment', 'roast', 'content', 'text'],
      ),
      avatarUrl: _pickString(
        item,
        const <String>['user_avatar', 'avatar', 'avatar_url'],
      ).isNotEmpty
          ? _pickString(
              item,
              const <String>['user_avatar', 'avatar', 'avatar_url'],
            )
          : _pickString(
              user,
              const <String>['avatar', 'avatar_url', 'user_avatar'],
            ),
      likeCount: _pickNullableInt(
        item,
        const <String>[
          'like_count',
          'likes',
          'thumbs_count',
          'praise_count',
          'up_count',
          'up',
        ],
      ),
    );
  }

  List<Map<String, Object?>> _extractList(Object? source) {
    if (source is List) {
      return source.whereType<Map>().map(_asMap).toList(growable: false);
    }
    if (source is Map) {
      final Map<String, Object?> map = _asMap(source);
      for (final String key in <String>[
        'list',
        'items',
        'comics',
        'results',
        'records',
        'browse',
        'browses',
      ]) {
        final Object? nested = map[key];
        if (nested is List) {
          return nested.whereType<Map>().map(_asMap).toList(growable: false);
        }
      }
    }
    return const <Map<String, Object?>>[];
  }

  Map<String, Object?> _firstNonEmptyMap(
    Map<String, Object?> source,
    List<String> keys,
  ) {
    for (final String key in keys) {
      final Map<String, Object?> value = _asMap(source[key]);
      if (value.isNotEmpty) {
        return value;
      }
    }
    return const <String, Object?>{};
  }

  String _buildComicHref(
    String pathWord,
    Map<String, Object?> primary,
    Map<String, Object?> fallback,
  ) {
    if (pathWord.isNotEmpty) {
      return AppConfig.resolvePath('/comic/$pathWord').toString();
    }
    final String directHref = _pickString(primary, <String>['href', 'url']);
    if (directHref.isNotEmpty) {
      return AppConfig.resolveNavigationUri(directHref).toString();
    }
    final String fallbackHref = _pickString(fallback, <String>['href', 'url']);
    if (fallbackHref.isNotEmpty) {
      return AppConfig.resolveNavigationUri(fallbackHref).toString();
    }
    return '';
  }

  String _buildChapterHref(String pathWord, String chapterUuid) {
    if (pathWord.isEmpty || chapterUuid.isEmpty) {
      return '';
    }
    return AppConfig.resolvePath(
      '/comic/$pathWord/chapter/$chapterUuid',
    ).toString();
  }

  String _searchAuthorLabel(Map<String, Object?> source) {
    final Object? authorValue = source['author'];
    if (authorValue is List) {
      final List<String> labels = authorValue
          .whereType<Map>()
          .map(
            (Map value) => _pickString(
              value.map(
                (Object? key, Object? nested) =>
                    MapEntry(key.toString(), nested),
              ),
              const <String>['name', 'author_name', 'title'],
            ),
          )
          .where((String value) => value.isNotEmpty)
          .toList(growable: false);
      if (labels.isNotEmpty) {
        return labels.join(' / ');
      }
    }
    return _pickString(source, const <String>['author_name', 'author']);
  }

  Map<String, Object?> _asMap(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return value.map(
        (Object? key, Object? nested) => MapEntry(key.toString(), nested),
      );
    }
    return const <String, Object?>{};
  }

  String _pickString(Map<String, Object?> source, List<String> keys) {
    for (final String key in keys) {
      final Object? value = source[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return '';
  }

  int _pickInt(
    Map<String, Object?> source,
    List<String> keys, {
    int fallback = 0,
  }) {
    for (final String key in keys) {
      final Object? value = source[key];
      if (value is num) {
        return value.toInt();
      }
      if (value is String) {
        final int? parsed = int.tryParse(value.trim());
        if (parsed != null) {
          return parsed;
        }
      }
    }
    return fallback;
  }

  bool _pickBool(Map<String, Object?> source, String key) {
    final Object? value = source[key];
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      return value == '1' || value.toLowerCase() == 'true';
    }
    return false;
  }

  int? _pickNullableInt(Map<String, Object?> source, List<String> keys) {
    for (final String key in keys) {
      final Object? value = source[key];
      if (value is num) {
        return value.toInt();
      }
      if (value is String) {
        final int? parsed = int.tryParse(value.trim());
        if (parsed != null) {
          return parsed;
        }
      }
    }
    return null;
  }

  Map<String, String> _buildRequestHeaders({
    bool includeAuth = false,
    String accept = 'application/json',
    String? contentType,
  }) {
    return <String, String>{
      'Accept': accept,
      if (contentType != null) 'Content-Type': contentType,
      'User-Agent': AppConfig.desktopUserAgent,
      'platform': '2',
      if (includeAuth && (_session.token ?? '').isNotEmpty)
        'Authorization': 'Token ${_session.token}',
      if (_session.cookieHeader.isNotEmpty) 'Cookie': _session.cookieHeader,
    };
  }

  Map<String, Object?> _decodeJsonMap(
    http.Response response, {
    required String malformedMessage,
  }) {
    final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw SiteApiException(malformedMessage);
    }
    return decoded.map(
      (Object? key, Object? value) => MapEntry(key.toString(), value),
    );
  }

  int _compareProfileLibraryItemByUpdatedAtDesc(
    ProfileLibraryItem left,
    ProfileLibraryItem right,
  ) {
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
