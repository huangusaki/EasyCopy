import 'dart:convert';

import 'package:easy_copy/config/app_config.dart';
import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/services/site_session.dart';
import 'package:http/http.dart' as http;

class SiteApiException implements Exception {
  SiteApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SiteApiClient {
  SiteApiClient({
    http.Client? client,
    SiteSession? session,
  }) : _client = client ?? http.Client(),
       _session = session ?? SiteSession.instance;

  static final SiteApiClient instance = SiteApiClient();

  final http.Client _client;
  final SiteSession _session;

  Future<ProfilePageData> loadProfile() async {
    await _session.ensureInitialized();
    if (!_session.isAuthenticated || (_session.token ?? '').isEmpty) {
      return ProfilePageData.loggedOut(uri: AppConfig.profileUri.toString());
    }

    final Future<Map<String, Object?>> userFuture = _getJson(
      '/api/v2/web/user/info',
    );
    final Future<Map<String, Object?>> collectionsFuture = _getJson(
      '/api/v3/member/collect/comics',
    );
    final Future<Map<String, Object?>> historyFuture = _getJson(
      '/api/v2/web/browses',
    );

    final List<Map<String, Object?>> responses = await Future.wait(
      <Future<Map<String, Object?>>>[
        userFuture,
        collectionsFuture,
        historyFuture,
      ],
    );

    final ProfileUserData user = _parseUser(responses[0]);
    await _session.bindUserId(user.userId);
    final List<ProfileLibraryItem> collections = _parseCollections(
      responses[1]['results'],
    );
    final List<ProfileHistoryItem> history = _parseHistory(
      responses[2]['results'],
    );

    return ProfilePageData(
      title: '我的',
      uri: AppConfig.profileUri.toString(),
      isLoggedIn: true,
      user: user,
      collections: collections,
      history: history,
      continueReading: history.isEmpty ? null : history.first,
    );
  }

  Future<Map<String, Object?>> _getJson(String path) async {
    final Uri uri = AppConfig.resolvePath(path);
    final http.Response response = await _client.get(
      uri,
      headers: <String, String>{
        'Authorization': 'Token ${_session.token}',
        'Accept': 'application/json',
        'Content-Type': 'application/x-www-form-urlencoded',
        'User-Agent': AppConfig.desktopUserAgent,
        'platform': '2',
      },
    );
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw SiteApiException('登录已失效，请重新登录。');
    }
    final Object? decoded = jsonDecode(
      utf8.decode(response.bodyBytes),
    );
    if (decoded is! Map) {
      throw SiteApiException('接口返回格式异常。');
    }
    final Map<String, Object?> payload = decoded.map(
      (Object? key, Object? value) => MapEntry(key.toString(), value),
    );
    final int code = (payload['code'] as num?)?.toInt() ?? response.statusCode;
    if (code != 200) {
      throw SiteApiException(
        (payload['message'] as String?) ?? '接口请求失败：$code',
      );
    }
    return payload;
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
    final String nickname = _pickString(results, <String>[
      'nickname',
      'name',
    ]);
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
    return _extractList(results)
        .map((Map<String, Object?> item) {
          final Map<String, Object?> comic = _firstNonEmptyMap(
            item,
            <String>['comic', 'comic_info', 'cartoon', 'results'],
          );
          final Map<String, Object?> source = comic.isEmpty ? item : comic;
          final String pathWord = _pickString(source, <String>[
            'path_word',
            'pathWord',
            'slug',
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
          );
        })
        .where((ProfileLibraryItem item) => item.title.isNotEmpty)
        .toList(growable: false);
  }

  List<ProfileHistoryItem> _parseHistory(Object? results) {
    return _extractList(results)
        .map((Map<String, Object?> item) {
          final Map<String, Object?> comic = _firstNonEmptyMap(
            item,
            <String>['comic', 'comic_info', 'cartoon'],
          );
          final Map<String, Object?> chapter = _firstNonEmptyMap(
            item,
            <String>['chapter', 'last_chapter'],
          );
          final Map<String, Object?> source = comic.isEmpty ? item : comic;
          final String pathWord = _pickString(source, <String>[
            'path_word',
            'pathWord',
            'slug',
          ]);
          final String chapterUuid = _pickString(chapter, <String>[
            'uuid',
            'chapter_uuid',
            'id',
          ]);
          return ProfileHistoryItem(
            title: _pickString(source, <String>['name', 'title']),
            coverUrl: _pickString(source, <String>[
              'cover',
              'cover_url',
              'image',
            ]),
            comicHref: _buildComicHref(pathWord, source, item),
            chapterLabel: _pickString(chapter, <String>[
              'name',
              'title',
              'chapter_name',
            ]),
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
    return AppConfig.resolvePath('/comic/$pathWord/chapter/$chapterUuid')
        .toString();
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
}
