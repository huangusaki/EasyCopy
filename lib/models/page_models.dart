import 'package:flutter/foundation.dart';

enum EasyCopyPageType { home, discover, rank, detail, reader, profile, unknown }

EasyCopyPageType _pageTypeFromWire(String value) {
  switch (value) {
    case 'home':
      return EasyCopyPageType.home;
    case 'discover':
      return EasyCopyPageType.discover;
    case 'rank':
      return EasyCopyPageType.rank;
    case 'detail':
      return EasyCopyPageType.detail;
    case 'reader':
      return EasyCopyPageType.reader;
    case 'profile':
      return EasyCopyPageType.profile;
    default:
      return EasyCopyPageType.unknown;
  }
}

String _stringValue(Object? value, {String fallback = ''}) {
  if (value is String) {
    return value;
  }
  return fallback;
}

bool _boolValue(Object? value, {bool fallback = false}) {
  if (value is bool) {
    return value;
  }
  return fallback;
}

List<Object?> _listValue(Object? value) {
  if (value is List<Object?>) {
    return value;
  }
  if (value is List) {
    return value.cast<Object?>();
  }
  return const <Object?>[];
}

Map<String, Object?> _mapValue(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (Object? key, Object? value) => MapEntry(key.toString(), value),
    );
  }
  return const <String, Object?>{};
}

List<T> _readList<T>(
  Map<String, Object?> source,
  String key,
  T Function(Map<String, Object?> json) fromJson,
) {
  return _listValue(source[key])
      .map(_mapValue)
      .where((Map<String, Object?> value) => value.isNotEmpty)
      .map(fromJson)
      .toList(growable: false);
}

@immutable
class LinkAction {
  const LinkAction({
    required this.label,
    required this.href,
    this.active = false,
  });

  factory LinkAction.fromJson(Map<String, Object?> json) {
    return LinkAction(
      label: _stringValue(json['label']),
      href: _stringValue(json['href']),
      active: _boolValue(json['active']),
    );
  }

  final String label;
  final String href;
  final bool active;

  bool get isNavigable => href.isNotEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'label': label,
      'href': href,
      'active': active,
    };
  }
}

@immutable
class HeroBannerData {
  const HeroBannerData({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.href,
  });

  factory HeroBannerData.fromJson(Map<String, Object?> json) {
    return HeroBannerData(
      title: _stringValue(json['title']),
      subtitle: _stringValue(json['subtitle']),
      imageUrl: _stringValue(json['imageUrl']),
      href: _stringValue(json['href']),
    );
  }

  final String title;
  final String subtitle;
  final String imageUrl;
  final String href;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'title': title,
      'subtitle': subtitle,
      'imageUrl': imageUrl,
      'href': href,
    };
  }
}

@immutable
class ComicCardData {
  const ComicCardData({
    required this.title,
    required this.coverUrl,
    required this.href,
    this.subtitle = '',
    this.secondaryText = '',
    this.badge = '',
  });

  factory ComicCardData.fromJson(Map<String, Object?> json) {
    return ComicCardData(
      title: _stringValue(json['title']),
      subtitle: _stringValue(json['subtitle']),
      secondaryText: _stringValue(json['secondaryText']),
      coverUrl: _stringValue(json['coverUrl']),
      href: _stringValue(json['href']),
      badge: _stringValue(json['badge']),
    );
  }

  final String title;
  final String subtitle;
  final String secondaryText;
  final String coverUrl;
  final String href;
  final String badge;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'title': title,
      'subtitle': subtitle,
      'secondaryText': secondaryText,
      'coverUrl': coverUrl,
      'href': href,
      'badge': badge,
    };
  }
}

@immutable
class ComicSectionData {
  const ComicSectionData({
    required this.title,
    required this.items,
    this.subtitle = '',
    this.href = '',
  });

  factory ComicSectionData.fromJson(Map<String, Object?> json) {
    return ComicSectionData(
      title: _stringValue(json['title']),
      subtitle: _stringValue(json['subtitle']),
      href: _stringValue(json['href']),
      items: _readList<ComicCardData>(json, 'items', ComicCardData.fromJson),
    );
  }

  final String title;
  final String subtitle;
  final String href;
  final List<ComicCardData> items;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'title': title,
      'subtitle': subtitle,
      'href': href,
      'items': items.map((ComicCardData item) => item.toJson()).toList(),
    };
  }
}

@immutable
class FilterGroupData {
  const FilterGroupData({required this.label, required this.options});

  factory FilterGroupData.fromJson(Map<String, Object?> json) {
    return FilterGroupData(
      label: _stringValue(json['label']),
      options: _readList<LinkAction>(json, 'options', LinkAction.fromJson),
    );
  }

  final String label;
  final List<LinkAction> options;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'label': label,
      'options': options.map((LinkAction item) => item.toJson()).toList(),
    };
  }
}

@immutable
class PagerData {
  const PagerData({
    this.currentLabel = '',
    this.totalLabel = '',
    this.prevHref = '',
    this.nextHref = '',
  });

  factory PagerData.fromJson(Map<String, Object?> json) {
    return PagerData(
      currentLabel: _stringValue(json['currentLabel']),
      totalLabel: _stringValue(json['totalLabel']),
      prevHref: _stringValue(json['prevHref']),
      nextHref: _stringValue(json['nextHref']),
    );
  }

  final String currentLabel;
  final String totalLabel;
  final String prevHref;
  final String nextHref;

  bool get hasPrev => prevHref.isNotEmpty;
  bool get hasNext => nextHref.isNotEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'currentLabel': currentLabel,
      'totalLabel': totalLabel,
      'prevHref': prevHref,
      'nextHref': nextHref,
    };
  }
}

@immutable
class RankEntryData {
  const RankEntryData({
    required this.rankLabel,
    required this.title,
    required this.coverUrl,
    required this.href,
    this.authors = '',
    this.heat = '',
    this.trend = '',
  });

  factory RankEntryData.fromJson(Map<String, Object?> json) {
    return RankEntryData(
      rankLabel: _stringValue(json['rankLabel']),
      title: _stringValue(json['title']),
      coverUrl: _stringValue(json['coverUrl']),
      href: _stringValue(json['href']),
      authors: _stringValue(json['authors']),
      heat: _stringValue(json['heat']),
      trend: _stringValue(json['trend']),
    );
  }

  final String rankLabel;
  final String title;
  final String authors;
  final String heat;
  final String trend;
  final String coverUrl;
  final String href;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'rankLabel': rankLabel,
      'title': title,
      'authors': authors,
      'heat': heat,
      'trend': trend,
      'coverUrl': coverUrl,
      'href': href,
    };
  }
}

@immutable
class ChapterData {
  const ChapterData({
    required this.label,
    required this.href,
    this.subtitle = '',
  });

  factory ChapterData.fromJson(Map<String, Object?> json) {
    return ChapterData(
      label: _stringValue(json['label']),
      href: _stringValue(json['href']),
      subtitle: _stringValue(json['subtitle']),
    );
  }

  final String label;
  final String href;
  final String subtitle;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'label': label,
      'href': href,
      'subtitle': subtitle,
    };
  }
}

@immutable
class ChapterGroupData {
  const ChapterGroupData({required this.label, required this.chapters});

  factory ChapterGroupData.fromJson(Map<String, Object?> json) {
    return ChapterGroupData(
      label: _stringValue(json['label']),
      chapters: _readList<ChapterData>(json, 'chapters', ChapterData.fromJson),
    );
  }

  final String label;
  final List<ChapterData> chapters;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'label': label,
      'chapters': chapters
          .map((ChapterData chapter) => chapter.toJson())
          .toList(),
    };
  }
}

@immutable
class ProfileUserData {
  const ProfileUserData({
    required this.userId,
    required this.username,
    this.nickname = '',
    this.avatarUrl = '',
    this.createdAt = '',
    this.membershipLabel = '',
  });

  factory ProfileUserData.fromJson(Map<String, Object?> json) {
    return ProfileUserData(
      userId: _stringValue(json['userId']),
      username: _stringValue(json['username']),
      nickname: _stringValue(json['nickname']),
      avatarUrl: _stringValue(json['avatarUrl']),
      createdAt: _stringValue(json['createdAt']),
      membershipLabel: _stringValue(json['membershipLabel']),
    );
  }

  final String userId;
  final String username;
  final String nickname;
  final String avatarUrl;
  final String createdAt;
  final String membershipLabel;

  String get displayName => nickname.isNotEmpty ? nickname : username;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'userId': userId,
      'username': username,
      'nickname': nickname,
      'avatarUrl': avatarUrl,
      'createdAt': createdAt,
      'membershipLabel': membershipLabel,
    };
  }
}

@immutable
class ProfileLibraryItem {
  const ProfileLibraryItem({
    required this.title,
    required this.coverUrl,
    required this.href,
    this.subtitle = '',
    this.secondaryText = '',
  });

  factory ProfileLibraryItem.fromJson(Map<String, Object?> json) {
    return ProfileLibraryItem(
      title: _stringValue(json['title']),
      coverUrl: _stringValue(json['coverUrl']),
      href: _stringValue(json['href']),
      subtitle: _stringValue(json['subtitle']),
      secondaryText: _stringValue(json['secondaryText']),
    );
  }

  final String title;
  final String coverUrl;
  final String href;
  final String subtitle;
  final String secondaryText;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'title': title,
      'coverUrl': coverUrl,
      'href': href,
      'subtitle': subtitle,
      'secondaryText': secondaryText,
    };
  }
}

@immutable
class ProfileHistoryItem {
  const ProfileHistoryItem({
    required this.title,
    required this.coverUrl,
    required this.comicHref,
    this.chapterLabel = '',
    this.chapterHref = '',
    this.visitedAt = '',
  });

  factory ProfileHistoryItem.fromJson(Map<String, Object?> json) {
    return ProfileHistoryItem(
      title: _stringValue(json['title']),
      coverUrl: _stringValue(json['coverUrl']),
      comicHref: _stringValue(json['comicHref']),
      chapterLabel: _stringValue(json['chapterLabel']),
      chapterHref: _stringValue(json['chapterHref']),
      visitedAt: _stringValue(json['visitedAt']),
    );
  }

  final String title;
  final String coverUrl;
  final String comicHref;
  final String chapterLabel;
  final String chapterHref;
  final String visitedAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'title': title,
      'coverUrl': coverUrl,
      'comicHref': comicHref,
      'chapterLabel': chapterLabel,
      'chapterHref': chapterHref,
      'visitedAt': visitedAt,
    };
  }
}

sealed class EasyCopyPage {
  const EasyCopyPage({
    required this.type,
    required this.title,
    required this.uri,
  });

  factory EasyCopyPage.fromJson(Map<String, Object?> json) {
    final EasyCopyPageType type = _pageTypeFromWire(_stringValue(json['type']));
    switch (type) {
      case EasyCopyPageType.home:
        return HomePageData.fromJson(json);
      case EasyCopyPageType.discover:
        return DiscoverPageData.fromJson(json);
      case EasyCopyPageType.rank:
        return RankPageData.fromJson(json);
      case EasyCopyPageType.detail:
        return DetailPageData.fromJson(json);
      case EasyCopyPageType.reader:
        return ReaderPageData.fromJson(json);
      case EasyCopyPageType.profile:
        return ProfilePageData.fromJson(json);
      case EasyCopyPageType.unknown:
        return UnknownPageData.fromJson(json);
    }
  }

  final EasyCopyPageType type;
  final String title;
  final String uri;

  Map<String, Object?> toJson();
}

class HomePageData extends EasyCopyPage {
  HomePageData({
    required super.title,
    required super.uri,
    required this.heroBanners,
    required this.sections,
    this.feature,
  }) : super(type: EasyCopyPageType.home);

  factory HomePageData.fromJson(Map<String, Object?> json) {
    return HomePageData(
      title: _stringValue(json['title'], fallback: '首頁'),
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
      ),
      feature: _mapValue(json['feature']).isEmpty
          ? null
          : HeroBannerData.fromJson(_mapValue(json['feature'])),
    );
  }

  final List<HeroBannerData> heroBanners;
  final List<ComicSectionData> sections;
  final HeroBannerData? feature;

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
      'feature': feature?.toJson(),
    };
  }
}

class DiscoverPageData extends EasyCopyPage {
  DiscoverPageData({
    required super.title,
    required super.uri,
    required this.filters,
    required this.items,
    required this.pager,
    required this.spotlight,
  }) : super(type: EasyCopyPageType.discover);

  factory DiscoverPageData.fromJson(Map<String, Object?> json) {
    return DiscoverPageData(
      title: _stringValue(json['title'], fallback: '發現'),
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

class RankPageData extends EasyCopyPage {
  RankPageData({
    required super.title,
    required super.uri,
    required this.categories,
    required this.periods,
    required this.items,
  }) : super(type: EasyCopyPageType.rank);

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
      'categories': categories
          .map((LinkAction item) => item.toJson())
          .toList(),
      'periods': periods.map((LinkAction item) => item.toJson()).toList(),
      'items': items.map((RankEntryData item) => item.toJson()).toList(),
    };
  }
}

class DetailPageData extends EasyCopyPage {
  DetailPageData({
    required super.title,
    required super.uri,
    required this.coverUrl,
    required this.aliases,
    required this.authors,
    required this.heat,
    required this.updatedAt,
    required this.status,
    required this.summary,
    required this.tags,
    required this.startReadingHref,
    required this.chapterGroups,
    required this.chapters,
  }) : super(type: EasyCopyPageType.detail);

  factory DetailPageData.fromJson(Map<String, Object?> json) {
    return DetailPageData(
      title: _stringValue(json['title']),
      uri: _stringValue(json['uri']),
      coverUrl: _stringValue(json['coverUrl']),
      aliases: _stringValue(json['aliases']),
      authors: _stringValue(json['authors']),
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
    );
  }

  final String coverUrl;
  final String aliases;
  final String authors;
  final String heat;
  final String updatedAt;
  final String status;
  final String summary;
  final List<LinkAction> tags;
  final String startReadingHref;
  final List<ChapterGroupData> chapterGroups;
  final List<ChapterData> chapters;

  @override
  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': 'detail',
      'title': title,
      'uri': uri,
      'coverUrl': coverUrl,
      'aliases': aliases,
      'authors': authors,
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
    };
  }
}

class ReaderPageData extends EasyCopyPage {
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
  }) : super(type: EasyCopyPageType.reader);

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

class ProfilePageData extends EasyCopyPage {
  ProfilePageData({
    required super.title,
    required super.uri,
    required this.isLoggedIn,
    this.user,
    this.continueReading,
    this.collections = const <ProfileLibraryItem>[],
    this.history = const <ProfileHistoryItem>[],
    this.message = '',
  }) : super(type: EasyCopyPageType.profile);

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
      message: _stringValue(json['message']),
    );
  }

  factory ProfilePageData.loggedOut({
    required String uri,
    String title = '我的',
    String message = '登录后可查看收藏、历史和继续阅读。',
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
  final String message;

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
      'message': message,
    };
  }
}

class UnknownPageData extends EasyCopyPage {
  UnknownPageData({
    required super.title,
    required super.uri,
    required this.message,
  }) : super(type: EasyCopyPageType.unknown);

  factory UnknownPageData.fromJson(Map<String, Object?> json) {
    return UnknownPageData(
      title: _stringValue(json['title'], fallback: '未支援頁面'),
      uri: _stringValue(json['uri']),
      message: _stringValue(json['message'], fallback: '這個頁面還沒有完成原生重建。'),
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
