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
    return ProfileUserData(
      userId: userId,
      username: username.isEmpty ? '未命名用户' : username,
      nickname: nickname,
    );
  }

  List<ProfileLibraryItem> _parseCollections(
    List<Map<String, Object?>> results, {
    ProfileCollectionSort sort = AppConfig.defaultProfileCollectionSort,
  }) {
    final List<ProfileLibraryItem> items = results
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
          final String updatedAt = pickFirstString(
            <Map<String, Object?>>[source, item],
            const <String>[
              'datetime_updated',
              'updated_at',
              'updatedAt',
              'last_update_time',
              'last_update_at',
              'update_time',
            ],
          );
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

  List<ProfileHistoryItem> _parseHistory(List<Map<String, Object?>> results) {
    return results
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
          final String chapterUuidFromChapter = pickString(
            chapter,
            const <String>['uuid', 'chapter_uuid', 'id'],
          );
          final String chapterUuid = chapterUuidFromChapter.isNotEmpty
              ? chapterUuidFromChapter
              : pickString(item, const <String>['last_chapter_id']);
          final String chapterLabelFromChapter = pickString(
            chapter,
            const <String>['name', 'title', 'chapter_name'],
          );
          final String chapterLabel = chapterLabelFromChapter.isNotEmpty
              ? chapterLabelFromChapter
              : pickString(item, const <String>['last_chapter_name']);
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
    final Map<String, Object?> nestedSource = _firstNonEmptyMap(
      item,
      const <String>['comic', 'comic_info', 'cartoon', 'results'],
    );
    final Map<String, Object?> source = nestedSource.isEmpty
        ? item
        : nestedSource;
    final String pathWord = pickString(source, <String>[
      'path_word',
      'pathWord',
      'slug',
    ]);
    final authors = _searchAuthorLinks(source);
    final authorText = authors.isEmpty
        ? pickString(source, const ['author_name', 'author'])
        : authors.map((author) => author.label).join(' / ');
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
      authorLinks: authors,
    );
  }

  ChapterComment _parseChapterComment(Map<String, Object?> item) {
    final Map<String, Object?> user = _firstNonEmptyMap(item, const <String>[
      'user',
      'member',
      'author',
    ]);
    final int commentId = pickInt(item, const <String>['id'], fallback: 0);
    final String itemAvatar = pickString(item, const <String>[
      'user_avatar',
      'avatar',
      'avatar_url',
    ]);
    final String avatarUrl = itemAvatar.isNotEmpty
        ? itemAvatar
        : pickString(user, const <String>[
            'avatar',
            'avatar_url',
            'user_avatar',
          ]);
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
      avatarUrl: avatarUrl,
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

  List<LinkAction> _searchAuthorLinks(Map<String, Object?> source) {
    final Object? authorValue = source['author'];
    if (authorValue is! List) {
      return const <LinkAction>[];
    }
    return authorValue
        .whereType<Map>()
        .map((Map value) {
          final Map<String, Object?> author = value.map(
            (Object? key, Object? nested) => MapEntry(key.toString(), nested),
          );
          final String label = pickString(author, const <String>[
            'name',
            'author_name',
            'title',
          ]);
          final String directHref = pickString(author, const <String>[
            'href',
            'url',
          ]);
          final String pathWord = pickString(author, const <String>[
            'path_word',
            'pathWord',
            'slug',
          ]);
          final String href = directHref.isNotEmpty
              ? AppConfig.resolveNavigationUri(directHref).toString()
              : pathWord.isEmpty
              ? ''
              : AppConfig.resolvePath('/author/$pathWord').toString();
          return LinkAction(label: label, href: href);
        })
        .where((LinkAction author) {
          return author.label.isNotEmpty;
        })
        .toList(growable: false);
  }
}
