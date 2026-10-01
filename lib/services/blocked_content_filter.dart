import 'package:reader/models/blocked_content.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/services/blocked_content_store.dart';
import 'package:reader/services/uri_keys.dart';

class BlockedContentFilter {
  const BlockedContentFilter(this.store);

  final BlockedContentStore store;

  SitePage apply(SitePage page) {
    if (store.items.isEmpty) {
      return page;
    }
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
                  authors: authorLinksFromText(item.authors),
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
          (ComicCardData item) =>
              !_isComicBlocked(href: item.href, authors: item.resolvedAuthors),
        )
        .toList(growable: false);
  }

  bool _isComicBlocked({
    required String href,
    required List<LinkAction> authors,
  }) {
    final String comicKey = UriKeys.rawPathKey(href);
    if (comicKey.isNotEmpty &&
        store.items.any(
          (BlockedContentItem item) =>
              item.type == BlockedContentType.comic && item.key == comicKey,
        )) {
      return true;
    }

    for (final BlockedContentItem rule in store.items) {
      if (rule.type != BlockedContentType.author) {
        continue;
      }
      final String rulePath = UriKeys.rawPathKey(rule.href);
      final String ruleName = BlockedContentStore.normalizeLabel(rule.label);
      for (final LinkAction author in authors) {
        final String authorPath = UriKeys.rawPathKey(author.href);
        if (rulePath.isNotEmpty && authorPath.isNotEmpty) {
          if (rulePath == authorPath) {
            return true;
          }
        } else if (ruleName.isNotEmpty &&
            ruleName == BlockedContentStore.normalizeLabel(author.label)) {
          return true;
        }
      }
    }
    return false;
  }
}
