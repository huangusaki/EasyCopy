import 'package:reader/models/blocked_content.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/services/blocked_content_store.dart';
import 'package:reader/services/uri_keys.dart';

class BlockedContentFilter {
  BlockedContentFilter(this.store);

  final BlockedContentStore store;

  List<BlockedContentItem>? _rules;
  final Set<String> _comics = {};
  final Set<String> _authorPaths = {};
  final Set<String> _authorNames = {};
  final Set<String> _namesWithoutPath = {};
  SitePage? _lastPage;
  SitePage? _lastView;

  SitePage apply(SitePage page) {
    final rules = store.items;
    if (!identical(rules, _rules)) {
      _rules = rules;
      _lastPage = _lastView = null;
      _comics.clear();
      _authorPaths.clear();
      _authorNames.clear();
      _namesWithoutPath.clear();
      for (final rule in rules) {
        if (rule.type == BlockedContentType.comic) {
          _comics.add(rule.key);
        } else {
          final path = UriKeys.rawPathKey(rule.href);
          final name = BlockedContentStore.normalizeLabel(rule.label);
          if (path.isNotEmpty) _authorPaths.add(path);
          if (name.isNotEmpty) {
            _authorNames.add(name);
            if (path.isEmpty) _namesWithoutPath.add(name);
          }
        }
      }
    }
    if (rules.isEmpty) return page;
    if (page is! HomePageData &&
        page is! DiscoverPageData &&
        page is! RankPageData) {
      return page;
    }
    if (identical(_lastPage, page)) return _lastView!;
    _lastPage = page;
    return _lastView = _filter(page);
  }

  SitePage _filter(SitePage page) {
    switch (page) {
      case HomePageData home:
        final List<ComicSectionData> sections = home.sections
            .map((ComicSectionData section) {
              return ComicSectionData(
                title: section.title,
                subtitle: section.subtitle,
                href: section.href,
                items: _filterCards(section.items),
              );
            })
            .where((ComicSectionData section) => section.items.isNotEmpty)
            .toList(growable: false);
        return HomePageData(
          title: home.title,
          uri: home.uri,
          sections: sections,
        );
      case DiscoverPageData discover:
        return discover.copyWith(items: _filterCards(discover.items));
      case RankPageData rank:
        return RankPageData(
          title: rank.title,
          uri: rank.uri,
          categories: rank.categories,
          periods: rank.periods,
          items: rank.items
              .where(
                (RankEntryData item) => !_isComicBlocked(
                  href: item.href,
                  authors: _hasAuthorRules
                      ? authorLinksFromText(item.authors)
                      : const [],
                ),
              )
              .toList(growable: false),
        );
      case DetailPageData _:
      case ReaderPageData _:
      case ProfilePageData _:
      case UnknownPageData _:
        return page;
    }
  }

  List<ComicCardData> _filterCards(List<ComicCardData> items) {
    return items
        .where(
          (ComicCardData item) => !_isComicBlocked(
            href: item.href,
            authors: _hasAuthorRules ? item.resolvedAuthors : const [],
          ),
        )
        .toList(growable: false);
  }

  bool get _hasAuthorRules =>
      _authorPaths.isNotEmpty || _authorNames.isNotEmpty;

  bool _isComicBlocked({
    required String href,
    required List<LinkAction> authors,
  }) {
    if (_comics.isNotEmpty && _comics.contains(UriKeys.rawPathKey(href))) {
      return true;
    }
    for (final author in authors) {
      final path = UriKeys.rawPathKey(author.href);
      if (path.isNotEmpty && _authorPaths.contains(path)) return true;
      final names = path.isEmpty ? _authorNames : _namesWithoutPath;
      if (names.isNotEmpty &&
          names.contains(BlockedContentStore.normalizeLabel(author.label))) {
        return true;
      }
    }
    return false;
  }
}
