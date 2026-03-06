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
    );
  }

  final String comicTitle;
  final String chapterTitle;
  final String progressLabel;
  final List<String> imageUrls;
  final String prevHref;
  final String nextHref;
  final String catalogHref;
}

class ProfilePageData extends EasyCopyPage {
  ProfilePageData({
    required super.title,
    required super.uri,
    required this.message,
  }) : super(type: EasyCopyPageType.profile);

  factory ProfilePageData.fromJson(Map<String, Object?> json) {
    return ProfilePageData(
      title: _stringValue(json['title'], fallback: '我的'),
      uri: _stringValue(json['uri']),
      message: _stringValue(
        json['message'],
        fallback: '個人中心正在重構，當前版本專注於首頁、發現、排行與閱讀體驗。',
      ),
    );
  }

  final String message;
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
}
