part of '../page_models.dart';

sealed class SitePage {
  const SitePage({required this.type, required this.title, required this.uri});

  factory SitePage.fromJson(Map<String, Object?> json) {
    final SitePageType type = _pageTypeFromWire(_stringValue(json['type']));
    switch (type) {
      case SitePageType.home:
        return HomePageData.fromJson(json);
      case SitePageType.discover:
        return DiscoverPageData.fromJson(json);
      case SitePageType.rank:
        return RankPageData.fromJson(json);
      case SitePageType.detail:
        return DetailPageData.fromJson(json);
      case SitePageType.reader:
        return ReaderPageData.fromJson(json);
      case SitePageType.profile:
        return ProfilePageData.fromJson(json);
      case SitePageType.unknown:
        return UnknownPageData.fromJson(json);
    }
  }

  final SitePageType type;
  final String title;
  final String uri;

  Map<String, Object?> toJson();
}

class HomePageData extends SitePage {
  HomePageData({
    required super.title,
    required super.uri,
    required this.heroBanners,
    required this.sections,
  }) : super(type: SitePageType.home);

  factory HomePageData.fromJson(Map<String, Object?> json) {
    return HomePageData(
      title: _stringValue(json['title'], fallback: '首页'),
      uri: _stringValue(json['uri']),
      heroBanners: _readList<HeroBannerData>(
        json,
        'heroBanners',
        HeroBannerData.fromJson,
      ),
      sections: _readList<ComicSectionData>(
        json,
        'sections',
        ComicSectionData.fromJson,
      ).where(_shouldRetainHomeSection).toList(growable: false),
    );
  }

  final List<HeroBannerData> heroBanners;
  final List<ComicSectionData> sections;

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': 'home',
      'title': title,
      'uri': uri,
      'heroBanners': heroBanners
          .map((HeroBannerData banner) => banner.toJson())
          .toList(),
      'sections': sections
          .map((ComicSectionData section) => section.toJson())
          .toList(),
    };
  }
}

class DiscoverPageData extends SitePage {
  DiscoverPageData({
    required super.title,
    required super.uri,
    required this.filters,
    required this.items,
    required this.pager,
    required this.spotlight,
  }) : super(type: SitePageType.discover);

  factory DiscoverPageData.fromJson(Map<String, Object?> json) {
    return DiscoverPageData(
      title: _stringValue(json['title'], fallback: '发现'),
      uri: _stringValue(json['uri']),
      filters: _readList<FilterGroupData>(
        json,
        'filters',
        FilterGroupData.fromJson,
      ),
      items: _readList<ComicCardData>(json, 'items', ComicCardData.fromJson),
      pager: PagerData.fromJson(_mapValue(json['pager'])),
      spotlight: _readList<ComicCardData>(
        json,
        'spotlight',
        ComicCardData.fromJson,
      ),
    );
  }

  final List<FilterGroupData> filters;
  final List<ComicCardData> items;
  final PagerData pager;
  final List<ComicCardData> spotlight;

  DiscoverPageData copyWith({
    String? title,
    String? uri,
    List<FilterGroupData>? filters,
    List<ComicCardData>? items,
    PagerData? pager,
    List<ComicCardData>? spotlight,
  }) {
    return DiscoverPageData(
      title: title ?? this.title,
      uri: uri ?? this.uri,
      filters: filters ?? this.filters,
      items: items ?? this.items,
      pager: pager ?? this.pager,
      spotlight: spotlight ?? this.spotlight,
    );
  }

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': 'discover',
      'title': title,
      'uri': uri,
      'filters': filters
          .map((FilterGroupData group) => group.toJson())
          .toList(),
      'items': items.map((ComicCardData item) => item.toJson()).toList(),
      'pager': pager.toJson(),
      'spotlight': spotlight
          .map((ComicCardData item) => item.toJson())
          .toList(),
    };
  }
}

class RankPageData extends SitePage {
  RankPageData({
    required super.title,
    required super.uri,
    required this.categories,
    required this.periods,
    required this.items,
  }) : super(type: SitePageType.rank);

  factory RankPageData.fromJson(Map<String, Object?> json) {
    return RankPageData(
      title: _stringValue(json['title'], fallback: '排行'),
      uri: _stringValue(json['uri']),
      categories: _readList<LinkAction>(
        json,
        'categories',
        LinkAction.fromJson,
      ),
      periods: _readList<LinkAction>(json, 'periods', LinkAction.fromJson),
      items: _readList<RankEntryData>(json, 'items', RankEntryData.fromJson),
    );
  }

  final List<LinkAction> categories;
  final List<LinkAction> periods;
  final List<RankEntryData> items;

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': 'rank',
      'title': title,
      'uri': uri,
      'categories': categories.map((LinkAction item) => item.toJson()).toList(),
      'periods': periods.map((LinkAction item) => item.toJson()).toList(),
      'items': items.map((RankEntryData item) => item.toJson()).toList(),
    };
  }
}

class DetailPageData extends SitePage {
  DetailPageData({
    required super.title,
    required super.uri,
    required this.coverUrl,
    required this.aliases,
    required this.authors,
    this.authorLinks = const <LinkAction>[],
    required this.heat,
    required this.updatedAt,
    required this.status,
    required this.summary,
    required this.tags,
    required this.startReadingHref,
    required this.chapterGroups,
    required this.chapters,
    this.comicId = '',
    this.isCollected = false,
  }) : super(type: SitePageType.detail);

  factory DetailPageData.fromJson(Map<String, Object?> json) {
    return DetailPageData(
      title: _stringValue(json['title']),
      uri: _stringValue(json['uri']),
      coverUrl: _stringValue(json['coverUrl']),
      aliases: _stringValue(json['aliases']),
      authors: _stringValue(json['authors']),
      authorLinks: _readList<LinkAction>(
        json,
        'authorLinks',
        LinkAction.fromJson,
      ),
      heat: _stringValue(json['heat']),
      updatedAt: _stringValue(json['updatedAt']),
      status: _stringValue(json['status']),
      summary: _stringValue(json['summary']),
      tags: _readList<LinkAction>(json, 'tags', LinkAction.fromJson),
      startReadingHref: _stringValue(json['startReadingHref']),
      chapterGroups: _readList<ChapterGroupData>(
        json,
        'chapterGroups',
        ChapterGroupData.fromJson,
      ),
      chapters: _readList<ChapterData>(json, 'chapters', ChapterData.fromJson),
      comicId: _stringValue(json['comicId']),
      isCollected: _boolValue(json['isCollected']),
    );
  }

  final String coverUrl;
  final String aliases;
  final String authors;
  final List<LinkAction> authorLinks;
  final String heat;
  final String updatedAt;
  final String status;
  final String summary;
  final List<LinkAction> tags;
  final String startReadingHref;
  final List<ChapterGroupData> chapterGroups;
  final List<ChapterData> chapters;
  final String comicId;
  final bool isCollected;

  CachedComicDetailSnapshot toCachedDetailSnapshot() {
    return CachedComicDetailSnapshot(
      aliases: aliases,
      authors: authors,
      authorLinks: authorLinks,
      heat: heat,
      updatedAt: updatedAt,
      status: status,
      summary: summary,
      tags: tags,
      startReadingHref: startReadingHref,
      totalChapterCount: chapters.length,
    );
  }

  DetailPageData copyWith({
    String? title,
    String? uri,
    String? coverUrl,
    String? aliases,
    String? authors,
    List<LinkAction>? authorLinks,
    String? heat,
    String? updatedAt,
    String? status,
    String? summary,
    List<LinkAction>? tags,
    String? startReadingHref,
    List<ChapterGroupData>? chapterGroups,
    List<ChapterData>? chapters,
    String? comicId,
    bool? isCollected,
  }) {
    return DetailPageData(
      title: title ?? this.title,
      uri: uri ?? this.uri,
      coverUrl: coverUrl ?? this.coverUrl,
      aliases: aliases ?? this.aliases,
      authors: authors ?? this.authors,
      authorLinks: authorLinks ?? this.authorLinks,
      heat: heat ?? this.heat,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ?? this.status,
      summary: summary ?? this.summary,
      tags: tags ?? this.tags,
      startReadingHref: startReadingHref ?? this.startReadingHref,
      chapterGroups: chapterGroups ?? this.chapterGroups,
      chapters: chapters ?? this.chapters,
      comicId: comicId ?? this.comicId,
      isCollected: isCollected ?? this.isCollected,
    );
  }

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': 'detail',
      'title': title,
      'uri': uri,
      'coverUrl': coverUrl,
      'aliases': aliases,
      'authors': authors,
      'authorLinks': authorLinks
          .map((LinkAction item) => item.toJson())
          .toList(),
      'heat': heat,
      'updatedAt': updatedAt,
      'status': status,
      'summary': summary,
      'tags': tags.map((LinkAction item) => item.toJson()).toList(),
      'startReadingHref': startReadingHref,
      'chapterGroups': chapterGroups
          .map((ChapterGroupData group) => group.toJson())
          .toList(),
      'chapters': chapters
          .map((ChapterData chapter) => chapter.toJson())
          .toList(),
      'comicId': comicId,
      'isCollected': isCollected,
    };
  }
}

@immutable
class CachedComicDetailSnapshot {
  const CachedComicDetailSnapshot({
    this.aliases = '',
    this.authors = '',
    this.authorLinks = const <LinkAction>[],
    this.heat = '',
    this.updatedAt = '',
    this.status = '',
    this.summary = '',
    this.tags = const <LinkAction>[],
    this.startReadingHref = '',
    this.totalChapterCount = 0,
  });

  factory CachedComicDetailSnapshot.fromJson(Map<String, Object?> json) {
    return CachedComicDetailSnapshot(
      aliases: _stringValue(json['aliases']),
      authors: _stringValue(json['authors']),
      authorLinks: _readList<LinkAction>(
        json,
        'authorLinks',
        LinkAction.fromJson,
      ),
      heat: _stringValue(json['heat']),
      updatedAt: _stringValue(json['updatedAt']),
      status: _stringValue(json['status']),
      summary: _stringValue(json['summary']),
      tags: _readList<LinkAction>(json, 'tags', LinkAction.fromJson),
      startReadingHref: _stringValue(json['startReadingHref']),
      totalChapterCount: _intValue(json['totalChapterCount']),
    );
  }

  final String aliases;
  final String authors;
  final List<LinkAction> authorLinks;
  final String heat;
  final String updatedAt;
  final String status;
  final String summary;
  final List<LinkAction> tags;
  final String startReadingHref;
  final int totalChapterCount;

  bool get isEmpty {
    return aliases.isEmpty &&
        authors.isEmpty &&
        heat.isEmpty &&
        updatedAt.isEmpty &&
        status.isEmpty &&
        summary.isEmpty &&
        startReadingHref.isEmpty &&
        tags.isEmpty &&
        totalChapterCount == 0;
  }

  CachedComicDetailSnapshot copyWith({
    String? aliases,
    String? authors,
    List<LinkAction>? authorLinks,
    String? heat,
    String? updatedAt,
    String? status,
    String? summary,
    List<LinkAction>? tags,
    String? startReadingHref,
    int? totalChapterCount,
  }) {
    return CachedComicDetailSnapshot(
      aliases: aliases ?? this.aliases,
      authors: authors ?? this.authors,
      authorLinks: authorLinks ?? this.authorLinks,
      heat: heat ?? this.heat,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ?? this.status,
      summary: summary ?? this.summary,
      tags: tags ?? this.tags,
      startReadingHref: startReadingHref ?? this.startReadingHref,
      totalChapterCount: totalChapterCount ?? this.totalChapterCount,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'aliases': aliases,
      'authors': authors,
      'authorLinks': authorLinks
          .map((LinkAction item) => item.toJson())
          .toList(),
      'heat': heat,
      'updatedAt': updatedAt,
      'status': status,
      'summary': summary,
      'tags': tags.map((LinkAction item) => item.toJson()).toList(),
      'startReadingHref': startReadingHref,
      'totalChapterCount': totalChapterCount,
    };
  }
}

class ReaderPageData extends SitePage {
  ReaderPageData({
    required super.title,
    required super.uri,
    required this.comicTitle,
    required this.chapterTitle,
    required this.progressLabel,
    required this.imageUrls,
    required this.prevHref,
    required this.nextHref,
    required this.catalogHref,
    this.contentKey = '',
  }) : super(type: SitePageType.reader);

  factory ReaderPageData.fromJson(Map<String, Object?> json) {
    return ReaderPageData(
      title: _stringValue(json['title']),
      uri: _stringValue(json['uri']),
      comicTitle: _stringValue(json['comicTitle']),
      chapterTitle: _stringValue(json['chapterTitle']),
      progressLabel: _stringValue(json['progressLabel']),
      imageUrls: _listValue(json['imageUrls'])
          .map((Object? value) => _stringValue(value))
          .where((String value) => value.isNotEmpty)
          .toList(growable: false),
      prevHref: _stringValue(json['prevHref']),
      nextHref: _stringValue(json['nextHref']),
      catalogHref: _stringValue(json['catalogHref']),
      contentKey: _stringValue(json['contentKey']),
    );
  }

  final String comicTitle;
  final String chapterTitle;
  final String progressLabel;
  final List<String> imageUrls;
  final String prevHref;
  final String nextHref;
  final String catalogHref;
  final String contentKey;

  bool get hasMissingChapterNavigation =>
      prevHref.trim().isEmpty || nextHref.trim().isEmpty;

  ReaderPageData copyWith({
    String? title,
    String? uri,
    String? comicTitle,
    String? chapterTitle,
    String? progressLabel,
    List<String>? imageUrls,
    String? prevHref,
    String? nextHref,
    String? catalogHref,
    String? contentKey,
  }) {
    return ReaderPageData(
      title: title ?? this.title,
      uri: uri ?? this.uri,
      comicTitle: comicTitle ?? this.comicTitle,
      chapterTitle: chapterTitle ?? this.chapterTitle,
      progressLabel: progressLabel ?? this.progressLabel,
      imageUrls: imageUrls ?? this.imageUrls,
      prevHref: prevHref ?? this.prevHref,
      nextHref: nextHref ?? this.nextHref,
      catalogHref: catalogHref ?? this.catalogHref,
      contentKey: contentKey ?? this.contentKey,
    );
  }

  ReaderPageData mergeMissingNavigation({
    String prevHref = '',
    String nextHref = '',
    String catalogHref = '',
  }) {
    return copyWith(
      prevHref: this.prevHref.trim().isNotEmpty ? this.prevHref : prevHref,
      nextHref: this.nextHref.trim().isNotEmpty ? this.nextHref : nextHref,
      catalogHref: this.catalogHref.trim().isNotEmpty
          ? this.catalogHref
          : catalogHref,
    );
  }

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': 'reader',
      'title': title,
      'uri': uri,
      'comicTitle': comicTitle,
      'chapterTitle': chapterTitle,
      'progressLabel': progressLabel,
      'imageUrls': imageUrls,
      'prevHref': prevHref,
      'nextHref': nextHref,
      'catalogHref': catalogHref,
      'contentKey': contentKey,
    };
  }
}

class ProfilePageData extends SitePage {
  ProfilePageData({
    required super.title,
    required super.uri,
    required this.isLoggedIn,
    this.user,
    this.continueReading,
    this.collections = const <ProfileLibraryItem>[],
    this.history = const <ProfileHistoryItem>[],
    this.collectionsPager = const PagerData(),
    this.historyPager = const PagerData(),
    this.collectionsTotal = 0,
    this.historyTotal = 0,
    this.message = '',
  }) : super(type: SitePageType.profile);

  factory ProfilePageData.fromJson(Map<String, Object?> json) {
    return ProfilePageData(
      title: _stringValue(json['title'], fallback: '我的'),
      uri: _stringValue(json['uri']),
      isLoggedIn: _boolValue(json['isLoggedIn']),
      user: _mapValue(json['user']).isEmpty
          ? null
          : ProfileUserData.fromJson(_mapValue(json['user'])),
      continueReading: _mapValue(json['continueReading']).isEmpty
          ? null
          : ProfileHistoryItem.fromJson(_mapValue(json['continueReading'])),
      collections: _readList<ProfileLibraryItem>(
        json,
        'collections',
        ProfileLibraryItem.fromJson,
      ),
      history: _readList<ProfileHistoryItem>(
        json,
        'history',
        ProfileHistoryItem.fromJson,
      ),
      collectionsPager: PagerData.fromJson(_mapValue(json['collectionsPager'])),
      historyPager: PagerData.fromJson(_mapValue(json['historyPager'])),
      collectionsTotal: _intValue(json['collectionsTotal']),
      historyTotal: _intValue(json['historyTotal']),
      message: _stringValue(json['message']),
    );
  }

  factory ProfilePageData.loggedOut({
    required String uri,
    String title = '我的',
    String message = '登录后可发表评论并查看账号信息。',
  }) {
    return ProfilePageData(
      title: title,
      uri: uri,
      isLoggedIn: false,
      message: message,
    );
  }

  final bool isLoggedIn;
  final ProfileUserData? user;
  final ProfileHistoryItem? continueReading;
  final List<ProfileLibraryItem> collections;
  final List<ProfileHistoryItem> history;
  final PagerData collectionsPager;
  final PagerData historyPager;
  final int collectionsTotal;
  final int historyTotal;
  final String message;

  ProfilePageData copyWith({
    String? title,
    String? uri,
    bool? isLoggedIn,
    ProfileUserData? user,
    bool clearUser = false,
    ProfileHistoryItem? continueReading,
    bool clearContinueReading = false,
    List<ProfileLibraryItem>? collections,
    List<ProfileHistoryItem>? history,
    PagerData? collectionsPager,
    PagerData? historyPager,
    int? collectionsTotal,
    int? historyTotal,
    String? message,
  }) {
    return ProfilePageData(
      title: title ?? this.title,
      uri: uri ?? this.uri,
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      user: clearUser ? null : (user ?? this.user),
      continueReading: clearContinueReading
          ? null
          : (continueReading ?? this.continueReading),
      collections: collections ?? this.collections,
      history: history ?? this.history,
      collectionsPager: collectionsPager ?? this.collectionsPager,
      historyPager: historyPager ?? this.historyPager,
      collectionsTotal: collectionsTotal ?? this.collectionsTotal,
      historyTotal: historyTotal ?? this.historyTotal,
      message: message ?? this.message,
    );
  }

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': 'profile',
      'title': title,
      'uri': uri,
      'isLoggedIn': isLoggedIn,
      'user': user?.toJson(),
      'continueReading': continueReading?.toJson(),
      'collections': collections
          .map((ProfileLibraryItem item) => item.toJson())
          .toList(),
      'history': history
          .map((ProfileHistoryItem item) => item.toJson())
          .toList(),
      'collectionsPager': collectionsPager.toJson(),
      'historyPager': historyPager.toJson(),
      'collectionsTotal': collectionsTotal,
      'historyTotal': historyTotal,
      'message': message,
    };
  }
}

class UnknownPageData extends SitePage {
  UnknownPageData({
    required super.title,
    required super.uri,
    required this.message,
  }) : super(type: SitePageType.unknown);

  factory UnknownPageData.fromJson(Map<String, Object?> json) {
    return UnknownPageData(
      title: _stringValue(json['title'], fallback: '未支持页面'),
      uri: _stringValue(json['uri']),
      message: _stringValue(json['message'], fallback: '这个页面还没有完成原生重建。'),
    );
  }

  final String message;

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': 'unknown',
      'title': title,
      'uri': uri,
      'message': message,
    };
  }
}
