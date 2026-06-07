part of '../site_api_client.dart';

extension _SiteApiParsing on SiteApiClient {
  ProfileUserData _parseUser(Map<String, Object?> payload) {
    final Map<String, Object?> results = asStringKeyMap(payload['results']);
    final String userId = pickString(results, <String>[
      'user_id',
      'id',
      'uuid',
    ]);
    final String username = pickString(results, <String>[
      'username',
      'mobile',
      'email',
    ]);
    final String nickname = pickString(results, <String>['nickname', 'name']);
    final String avatarUrl = pickString(results, <String>[
      'avatar',
      'avatar_url',
    ]);
    final String createdAt = pickString(results, <String>[
      'createDate',
      'datetime_created',
      'created_at',
    ]);
    final List<String> memberships = <String>[
      if (pickBool(results, 'vip')) 'VIP',
      if (pickBool(results, 'comic_vip')) '漫画会员',
      if (pickBool(results, 'cartoon_vip')) '动画会员',
    ];
    return ProfileUserData(
      userId: userId,
      username: username.isEmpty ? '未命名用户' : username,
      nickname: nickname,
      avatarUrl: avatarUrl,
      createdAt: createdAt,
      membershipLabel: memberships.isEmpty ? '普通会员' : memberships.join(' / '),
    );
  }

  List<ProfileLibraryItem> _parseCollections(
    Object? results, {
    ProfileCollectionSort sort = AppConfig.defaultProfileCollectionSort,
  }) {
    final List<ProfileLibraryItem> items = _extractList(results)
        .map((Map<String, Object?> item) {
          final Map<String, Object?> comic = _firstNonEmptyMap(item, <String>[
            'comic',
            'comic_info',
            'cartoon',
            'results',
          ]);
          final Map<String, Object?> source = comic.isEmpty ? item : comic;
          final String pathWord = pickString(source, <String>[
            'path_word',
            'pathWord',
            'slug',
          ]);
          final String updatedAt =
              pickString(source, <String>[
                'datetime_updated',
                'updated_at',
                'updatedAt',
                'last_update_time',
                'last_update_at',
                'update_time',
              ]).isNotEmpty
              ? pickString(source, <String>[
                  'datetime_updated',
                  'updated_at',
                  'updatedAt',
                  'last_update_time',
                  'last_update_at',
                  'update_time',
                ])
              : pickString(item, <String>[
                  'datetime_updated',
                  'updated_at',
                  'updatedAt',
                  'last_update_time',
                  'last_update_at',
                  'update_time',
                ]);
          return ProfileLibraryItem(
            title: pickString(source, <String>['name', 'title']),
            coverUrl: pickString(source, <String>[
              'cover',
              'cover_url',
              'image',
            ]),
            href: _buildComicHref(pathWord, source, item),
            subtitle: pickString(source, <String>[
              'author_name',
              'author',
              'subtitle',
            ]),
            secondaryText: pickString(source, <String>[
              'last_chapter_name',
              'datetime_updated',
              'status',
            ]),
            updatedAt: updatedAt,
          );
        })
        .where((ProfileLibraryItem item) => item.title.isNotEmpty)
        .toList(growable: false);
    switch (sort) {
      case ProfileCollectionSort.latestUpdate:
        items.sort(_compareByUpdatedDesc);
        break;
      case ProfileCollectionSort.readingTime:
      case ProfileCollectionSort.alphabetical:
        break;
    }
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
          final Map<String, Object?> browse = _firstNonEmptyMap(item, <String>[
            'browse',
            'last_browse',
          ]);
          final Map<String, Object?> source = comic.isEmpty ? item : comic;
          final String pathWord = pickString(source, <String>[
            'path_word',
            'pathWord',
            'slug',
          ]);
          final String chapterUuid =
              pickString(chapter, <String>[
                'uuid',
                'chapter_uuid',
                'id',
              ]).isNotEmpty
              ? pickString(chapter, <String>['uuid', 'chapter_uuid', 'id'])
              : pickString(item, <String>['last_chapter_id']);
          final String chapterLabel =
              pickString(chapter, <String>[
                'name',
                'title',
                'chapter_name',
              ]).isNotEmpty
              ? pickString(chapter, <String>['name', 'title', 'chapter_name'])
              : pickString(item, <String>['last_chapter_name']);
          return ProfileHistoryItem(
            title: pickString(source, <String>['name', 'title']),
            coverUrl: pickString(source, <String>[
              'cover',
              'cover_url',
              'image',
            ]),
            comicHref: _buildComicHref(pathWord, source, item),
            chapterLabel: chapterLabel,
            chapterHref: _buildChapterHref(pathWord, chapterUuid),
            visitedAt: pickFirstString(
              <Map<String, Object?>>[item, browse],
              const <String>[
                'datetime_created',
                'datetime_updated',
                'created_at',
                'updated_at',
                'browse_at',
                'browse_time',
                'read_at',
                'read_time',
              ],
            ),
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
    final String pathWord = pickString(source, <String>[
      'path_word',
      'pathWord',
      'slug',
    ]);
    final String authorText = _searchAuthorLabel(source);
    return ComicCardData(
      title: pickString(source, <String>['name', 'title']),
      subtitle: authorText.isEmpty ? '作者：--' : '作者：$authorText',
      secondaryText: pickString(source, <String>[
        'datetime_updated',
        'status',
        'brief',
      ]),
      coverUrl: pickString(source, <String>['cover', 'cover_url', 'image']),
      href: _buildComicHref(pathWord, source, item),
    );
  }

  ChapterComment _parseChapterComment(Map<String, Object?> item) {
    final Map<String, Object?> user = _firstNonEmptyMap(item, const <String>[
      'user',
      'member',
      'author',
    ]);
    final int commentId = pickInt(item, const <String>['id'], fallback: 0);
    return ChapterComment(
      id: commentId > 0
          ? '$commentId'
          : pickString(item, const <String>['uuid', 'comment_id', 'roast_id']),
      message: pickString(item, const <String>[
        'comment',
        'roast',
        'content',
        'text',
      ]),
      avatarUrl:
          pickString(item, const <String>[
            'user_avatar',
            'avatar',
            'avatar_url',
          ]).isNotEmpty
          ? pickString(item, const <String>[
              'user_avatar',
              'avatar',
              'avatar_url',
            ])
          : pickString(user, const <String>[
              'avatar',
              'avatar_url',
              'user_avatar',
            ]),
    );
  }

  List<Map<String, Object?>> _extractList(Object? source) {
    if (source is List) {
      return source
          .whereType<Map>()
          .map(asStringKeyMap)
          .toList(growable: false);
    }
    if (source is Map) {
      final Map<String, Object?> map = asStringKeyMap(source);
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
          return nested
              .whereType<Map>()
              .map(asStringKeyMap)
              .toList(growable: false);
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
      final Map<String, Object?> value = asStringKeyMap(source[key]);
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
    final String directHref = pickString(primary, <String>['href', 'url']);
    if (directHref.isNotEmpty) {
      return AppConfig.resolveNavigationUri(directHref).toString();
    }
    final String fallbackHref = pickString(fallback, <String>['href', 'url']);
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
            (Map value) => pickString(
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
    return pickString(source, const <String>['author_name', 'author']);
  }
}
