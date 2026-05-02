import 'package:easy_copy/models/page_models.dart';

class ChapterPickerSection {
  const ChapterPickerSection({required this.label, required this.chapters});

  final String label;
  final List<ChapterData> chapters;
}

class DetailChapterTabData {
  const DetailChapterTabData({
    required this.key,
    required this.label,
    required this.chapters,
  });

  final String key;
  final String label;
  final List<ChapterData> chapters;

  bool get enabled => chapters.isNotEmpty;
}

class AdjacentChapterLinks {
  const AdjacentChapterLinks({this.prevHref = '', this.nextHref = ''});

  final String prevHref;
  final String nextHref;
}

class CachedChapterNavigationContext {
  const CachedChapterNavigationContext({
    this.prevHref = '',
    this.nextHref = '',
    this.catalogHref = '',
  });

  final String prevHref;
  final String nextHref;
  final String catalogHref;

  bool get hasAnyValue =>
      prevHref.trim().isNotEmpty ||
      nextHref.trim().isNotEmpty ||
      catalogHref.trim().isNotEmpty;

  CachedChapterNavigationContext copyWith({
    String? prevHref,
    String? nextHref,
    String? catalogHref,
  }) {
    return CachedChapterNavigationContext(
      prevHref: prevHref ?? this.prevHref,
      nextHref: nextHref ?? this.nextHref,
      catalogHref: catalogHref ?? this.catalogHref,
    );
  }

  CachedChapterNavigationContext mergeMissing(
    CachedChapterNavigationContext fallback,
  ) {
    return CachedChapterNavigationContext(
      prevHref: prevHref.trim().isNotEmpty ? prevHref : fallback.prevHref,
      nextHref: nextHref.trim().isNotEmpty ? nextHref : fallback.nextHref,
      catalogHref: catalogHref.trim().isNotEmpty
          ? catalogHref
          : fallback.catalogHref,
    );
  }
}
