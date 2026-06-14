import 'package:flutter/foundation.dart';

part 'page_models/site_pages.dart';

enum SitePageType { home, discover, rank, detail, reader, profile, unknown }

SitePageType _pageTypeFromWire(String value) {
  switch (value) {
    case 'home':
      return SitePageType.home;
    case 'discover':
      return SitePageType.discover;
    case 'rank':
      return SitePageType.rank;
    case 'detail':
      return SitePageType.detail;
    case 'reader':
      return SitePageType.reader;
    case 'profile':
      return SitePageType.profile;
    default:
      return SitePageType.unknown;
  }
}

String _stringValue(Object? value, {String fallback = ''}) {
  if (value is String) {
    return value;
  }
  return fallback;
}

int? _firstPositiveInt(String value) {
  final Match? match = RegExp(r'(\d+)').firstMatch(value);
  if (match == null) {
    return null;
  }
  final int? parsed = int.tryParse(match.group(1)!);
  if (parsed == null || parsed < 1) {
    return null;
  }
  return parsed;
}

int? _pagerTotalPageCount(String value) {
  final Match? pageMatch = RegExp(r'(\d+)\s*页').firstMatch(value);
  if (pageMatch != null) {
    return int.tryParse(pageMatch.group(1)!);
  }
  final Match? slashMatch = RegExp(r'/\s*(\d+)').firstMatch(value);
  if (slashMatch != null) {
    return int.tryParse(slashMatch.group(1)!);
  }
  return _firstPositiveInt(value);
}

bool _boolValue(Object? value, {bool fallback = false}) {
  if (value is bool) {
    return value;
  }
  return fallback;
}

int _intValue(Object? value, {int fallback = 0}) {
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim()) ?? fallback;
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

bool shouldRetainHomeSection({required String title, required String href}) {
  final String normalizedTitle = title.replaceAll(RegExp(r'\s+'), '');
  final Uri? hrefUri = Uri.tryParse(href.trim());
  final String normalizedPath = (hrefUri?.path ?? href).trim().toLowerCase();
  return !normalizedTitle.contains('熱門更新') &&
      !normalizedTitle.contains('热门更新') &&
      normalizedPath != '/comics' &&
      normalizedPath != '/comics/';
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

  LinkAction copyWith({String? label, String? href, bool? active}) {
    return LinkAction(
      label: label ?? this.label,
      href: href ?? this.href,
      active: active ?? this.active,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{'label': label, 'href': href, 'active': active};
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

  FilterGroupData copyWith({String? label, List<LinkAction>? options}) {
    return FilterGroupData(
      label: label ?? this.label,
      options: options ?? this.options,
    );
  }

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

  int? get currentPageNumber => _firstPositiveInt(currentLabel);

  int? get totalPageCount => _pagerTotalPageCount(totalLabel);

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
    this.updatedAt = '',
  });

  factory ProfileLibraryItem.fromJson(Map<String, Object?> json) {
    return ProfileLibraryItem(
      title: _stringValue(json['title']),
      coverUrl: _stringValue(json['coverUrl']),
      href: _stringValue(json['href']),
      subtitle: _stringValue(json['subtitle']),
      secondaryText: _stringValue(json['secondaryText']),
      updatedAt: _stringValue(json['updatedAt']),
    );
  }

  final String title;
  final String coverUrl;
  final String href;
  final String subtitle;
  final String secondaryText;
  final String updatedAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'title': title,
      'coverUrl': coverUrl,
      'href': href,
      'subtitle': subtitle,
      'secondaryText': secondaryText,
      'updatedAt': updatedAt,
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
