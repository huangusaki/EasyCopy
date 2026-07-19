import 'dart:convert';
import 'dart:typed_data';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:pointycastle/export.dart';
import 'package:reader/config/app_config.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/services/js_literal_utils.dart';
import 'package:reader/services/site_json_utils.dart';

part 'site_html_page_parser/html_helpers.dart';

typedef DetailChapterResultsLoader =
    Future<String> Function(DetailChapterRequest request);

class SiteHtmlPageParseException implements Exception {
  SiteHtmlPageParseException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DetailChapterRequest {
  const DetailChapterRequest({
    required this.pageUri,
    required this.slug,
    required this.ccz,
    required this.dnt,
  });

  final Uri pageUri;
  final String slug;
  final String ccz;
  final String dnt;
}

// 与 WebView 注入脚本共享站点 DOM 约定，选择器变更需同步。
class SiteHtmlPageParser {
  const SiteHtmlPageParser();

  static const SiteHtmlPageParser instance = SiteHtmlPageParser();

  static final RegExp _spacePattern = RegExp(r'\s+');
  static final RegExp _hexPattern = RegExp(r'^[0-9a-fA-F]+$');

  Future<SitePage> parsePage(
    Uri uri,
    String html, {
    DetailChapterResultsLoader? loadDetailChapterResults,
  }) async {
    final Uri normalizedUri = AppConfig.rewriteToCurrentHost(uri);
    final dom.Document document = html_parser.parse(html);
    final SitePageType pageType = _detectPageType(normalizedUri, document);

    switch (pageType) {
      case SitePageType.home:
        return _buildHomePage(normalizedUri, document);
      case SitePageType.discover:
        return _buildDiscoverPage(normalizedUri, document);
      case SitePageType.rank:
        return _buildRankPage(normalizedUri, document);
      case SitePageType.detail:
        return _buildDetailPage(
          normalizedUri,
          html,
          document,
          loadDetailChapterResults: loadDetailChapterResults,
        );
      case SitePageType.reader:
        return _buildReaderPage(normalizedUri, html, document);
      case SitePageType.profile:
      case SitePageType.unknown:
        throw SiteHtmlPageParseException(
          '当前 HTML loader 不支持解析此页面：${normalizedUri.path}',
        );
    }
  }

  SitePageType _detectPageType(Uri uri, dom.Document document) {
    final String path = uri.path.toLowerCase();
    if (path.contains('/chapter/')) {
      return SitePageType.reader;
    }
    if (document.querySelector('.comicParticulars-title') != null) {
      return SitePageType.detail;
    }
    if (document.querySelector('.ranking-box') != null) {
      return SitePageType.rank;
    }
    if (document.querySelector('.exemptComicList') != null ||
        document.querySelector('.correlationList .exemptComic_Item') != null ||
        path.startsWith('/comics') ||
        path.startsWith('/filter') ||
        path.startsWith('/recommend') ||
        path.startsWith('/newest') ||
        path.startsWith('/author') ||
        path.startsWith('/search')) {
      return SitePageType.discover;
    }
    if (document.querySelector('.content-box .swiperList') != null ||
        document.querySelector('.comicRank') != null ||
        path == '/') {
      return SitePageType.home;
    }
    if (path.startsWith('/web/login') || path.startsWith('/person')) {
      return SitePageType.profile;
    }
    return SitePageType.unknown;
  }

  HomePageData _buildHomePage(Uri uri, dom.Document document) {
    final List<ComicSectionData> sections =
        _querySelectorAll(document, '.index-all-icon')
            .map((dom.Element header) {
              final String title = _queryText(
                header,
                '.index-all-icon-left-txt',
              );
              final String sectionHref = _linkUrl(
                uri,
                _querySelector(header, '.index-all-icon-right a'),
              );
              if (title.isEmpty || title.contains('排行榜')) {
                return null;
              }
              if (!shouldRetainHomeSection(title: title, href: sectionHref)) {
                return null;
              }

              final dom.Element? container = _parentElement(header);
              if (container == null) {
                return null;
              }
              final int headerIndex = container.children.indexOf(header);
              if (headerIndex < 0) {
                return null;
              }

              dom.Element? row;
              for (final dom.Element sibling in container.children.skip(
                headerIndex + 1,
              )) {
                if (sibling.classes.contains('row')) {
                  row = sibling;
                  break;
                }
              }
              if (row == null) {
                return null;
              }

              final List<ComicCardData> items = _collectComicCards(
                row,
                uri,
                'a[href*="/comic/"]',
              );
              if (items.isEmpty) {
                return null;
              }

              return ComicSectionData(
                title: title,
                subtitle: '',
                href: sectionHref,
                items: items,
              );
            })
            .whereType<ComicSectionData>()
            .toList(growable: false);

    return HomePageData(
      title: '首页',
      uri: uri.toString(),
      heroBanners: const <HeroBannerData>[],
      sections: sections,
    );
  }

  DiscoverPageData _buildDiscoverPage(Uri uri, dom.Document document) {
    List<ComicCardData> items = _collectComicCards(
      document,
      uri,
      '.exemptComic-box a[href*="/comic/"], '
      '.correlationList a[href*="/comic/"]',
    );
    if (items.isEmpty) {
      items = _discoverItemsFromInlineList(uri, document);
    }
    final dom.Element? pager = document.querySelector('.page-all');
    final List<dom.Element> totalLabels = pager == null
        ? const <dom.Element>[]
        : pager.querySelectorAll('.page-total').toList(growable: false);

    return DiscoverPageData(
      title: _pageTitle(document),
      uri: uri.toString(),
      filters: _collectFilterGroups(document, uri),
      items: items,
      pager: PagerData(
        currentLabel: _queryText(pager, '.page-all-item.active a'),
        totalLabel: totalLabels.isEmpty ? '' : _text(totalLabels.last),
        prevHref: _linkUrl(
          uri,
          _querySelector(pager, '.prev a') ??
              _querySelector(pager, '.prev-all a'),
        ),
        nextHref: _linkUrl(
          uri,
          _querySelector(pager, '.next a') ??
              _querySelector(pager, '.next-all a'),
        ),
      ),
      spotlight: _collectComicCards(
        document,
        uri,
        '.dailyRecommendation-box a[href*="/comic/"]',
      ),
    );
  }

  RankPageData _buildRankPage(Uri uri, dom.Document document) {
    final List<RankEntryData> items = _uniqueBy<RankEntryData>(
      _querySelectorAll(document, '.ranking-all-box').map((dom.Element card) {
        final dom.Element? coverAnchor = _querySelector(
          card,
          'a[href*="/comic/"]',
        );
        final String href = _linkUrl(uri, coverAnchor);
        final String title =
            _attr(_querySelector(card, '.threeLines'), 'title').isNotEmpty
            ? _attr(_querySelector(card, '.threeLines'), 'title')
            : _queryText(card, '.threeLines');
        if (title.isEmpty || href.isEmpty) {
          return null;
        }

        String trend = 'stable';
        final dom.Element? trendElement = _querySelector(card, '.update-icon');
        if (trendElement != null) {
          if (trendElement.classes.contains('up')) {
            trend = 'up';
          } else if (trendElement.classes.contains('end')) {
            trend = 'down';
          }
        }

        return RankEntryData(
          rankLabel: _queryText(card, '.ranking-all-icon'),
          title: title,
          authors: _queryText(card, '.oneLines'),
          heat: _queryText(card, '.update span'),
          trend: trend,
          coverUrl: _imageUrl(uri, _querySelector(card, 'img')),
          href: href,
        );
      }).whereType<RankEntryData>(),
      (RankEntryData item) => item.href,
    );

    return RankPageData(
      title: _queryText(document, '.ranking-box-title span').isNotEmpty
          ? _queryText(document, '.ranking-box-title span')
          : _pageTitle(document),
      uri: uri.toString(),
      categories: _collectFilterGroups(document, uri)
          .expand((FilterGroupData group) => group.options)
          .toList(growable: false),
      periods: _querySelectorAll(document, '.rankingTime a')
          .map((dom.Element anchor) {
            final String label = _text(anchor);
            final String href = _linkUrl(uri, anchor);
            if (label.isEmpty || href.isEmpty) {
              return null;
            }
            return LinkAction(
              label: label,
              href: href,
              active: anchor.classes.contains('active'),
            );
          })
          .whereType<LinkAction>()
          .toList(growable: false),
      items: items,
    );
  }

  ReaderPageData _buildReaderPage(Uri uri, String html, dom.Document document) {
    final String headerText = _queryText(document, 'h4.header');
    final String pageTitle = _pageTitle(document);
    final List<String> headerParts = headerText
        .split('/')
        .map(_cleanText)
        .where((String value) => value.isNotEmpty)
        .toList(growable: false);
    final List<String> titleParts = pageTitle
        .split(RegExp(r'\s*-\s*'))
        .map(_cleanText)
        .where((String value) => value.isNotEmpty)
        .toList(growable: false);
    final String contentKey = _scriptStringValue(html, 'contentKey');
    final String cct = _scriptStringValue(html, 'cct');

    List<String> imageUrls = const <String>[];
    if (contentKey.isNotEmpty && cct.isNotEmpty) {
      try {
        imageUrls = parseEncryptedReaderImageUrls(
          uri,
          contentKey: contentKey,
          cct: cct,
        );
      } catch (_) {
        imageUrls = const <String>[];
      }
    }
    if (imageUrls.isEmpty) {
      imageUrls = _collectReaderImageUrlsFromDom(document, uri);
    }
    if (imageUrls.isEmpty) {
      throw SiteHtmlPageParseException('阅读页图片解析失败：${uri.path}');
    }

    final String comicTitle = headerParts.isNotEmpty
        ? headerParts.first
        : titleParts.isNotEmpty
        ? titleParts.first
        : pageTitle;
    final String chapterTitle = headerParts.length > 1
        ? headerParts.skip(1).join('/')
        : titleParts.length > 1
        ? titleParts.skip(1).join(' - ')
        : '';

    return ReaderPageData(
      title: headerText.isNotEmpty ? headerText : pageTitle,
      uri: uri.toString(),
      comicTitle: comicTitle,
      chapterTitle: chapterTitle,
      progressLabel: _queryText(document, '.comicContent-footer-txt span'),
      imageUrls: imageUrls,
      prevHref: _linkUrl(
        uri,
        _querySelector(
          document,
          '.comicContent-prev:not(.index):not(.list) a[href]',
        ),
      ),
      nextHref: _linkUrl(
        uri,
        _querySelector(document, '.comicContent-next a[href]'),
      ),
      catalogHref: _linkUrl(
        uri,
        _querySelector(document, '.comicContent-prev.list a[href]'),
      ),
      contentKey: contentKey,
    );
  }

  Future<DetailPageData> _buildDetailPage(
    Uri uri,
    String html,
    dom.Document document, {
    DetailChapterResultsLoader? loadDetailChapterResults,
  }) async {
    final List<dom.Element> infoRows = _querySelectorAll(
      document,
      '.comicParticulars-title-right li',
    );
    final dom.Element? collectButton = _querySelector(
      document,
      '.comicParticulars-botton.collect',
    );
    final String collectText = _text(collectButton);
    final String comicId = extractJsCallStringArg(
      _attr(collectButton, 'onclick'),
      'collect',
    );
    final dom.Element? authorRow = _rowByPrefix(infoRows, '作者');

    List<ChapterGroupData> chapterGroups = const <ChapterGroupData>[];
    List<ChapterData> chapters = const <ChapterData>[];

    if (loadDetailChapterResults != null) {
      final DetailChapterRequest? request = _buildDetailChapterRequest(
        uri,
        html,
        document,
      );
      if (request != null) {
        try {
          final _ParsedDetailChapters parsed = _parseEncryptedDetailChapters(
            request,
            await loadDetailChapterResults(request),
          );
          if (parsed.chapterGroups.isNotEmpty || parsed.chapters.isNotEmpty) {
            chapterGroups = parsed.chapterGroups;
            chapters = parsed.chapters;
          }
        } catch (_) {
          chapterGroups = const <ChapterGroupData>[];
          chapters = const <ChapterData>[];
        }
      }
    }

    if (chapterGroups.isEmpty && chapters.isEmpty) {
      chapterGroups = _parseChapterGroupsFromDom(document, uri);
      chapters = _uniqueBy<ChapterData>(
        chapterGroups.expand((ChapterGroupData group) => group.chapters),
        (ChapterData chapter) => chapter.href,
      );
      if (chapters.isEmpty) {
        chapters = _collectChapterLinks(document, uri);
      }
    }

    if (chapterGroups.isEmpty && chapters.isEmpty) {
      throw SiteHtmlPageParseException('详情页章节解析失败：${uri.path}');
    }

    return DetailPageData(
      title: _attr(_querySelector(document, 'h6[title]'), 'title').isNotEmpty
          ? _attr(_querySelector(document, 'h6[title]'), 'title')
          : _pageTitle(document),
      uri: uri.toString(),
      coverUrl: _imageUrl(
        uri,
        _querySelector(document, '.comicParticulars-left-img img'),
      ),
      aliases: _infoValue(infoRows, '別名'),
      authors: _mapText(
        _querySelectorAll(authorRow ?? document, 'a').map(_text),
      ).join(' / '),
      authorLinks: _querySelectorAll(authorRow ?? document, 'a')
          .map((dom.Element anchor) {
            final String label = _text(anchor);
            final String href = _linkUrl(uri, anchor);
            if (label.isEmpty || href.isEmpty) {
              return null;
            }
            return LinkAction(label: label, href: href, active: false);
          })
          .whereType<LinkAction>()
          .toList(growable: false),
      heat: _infoValue(infoRows, '熱度'),
      updatedAt: _infoValue(infoRows, '最後更新'),
      status: _infoValue(infoRows, '狀態'),
      summary: _queryText(document, '.intro'),
      tags: _querySelectorAll(document, '.comicParticulars-tag a')
          .map((dom.Element anchor) {
            final String label = _text(anchor).replaceFirst(RegExp(r'^#'), '');
            final String href = _linkUrl(uri, anchor);
            if (label.isEmpty || href.isEmpty) {
              return null;
            }
            return LinkAction(label: label, href: href, active: false);
          })
          .whereType<LinkAction>()
          .toList(growable: false),
      comicId: comicId,
      isCollected:
          collectText.isNotEmpty &&
          !collectText.contains('加入書架') &&
          !collectText.contains('加入书架'),
      startReadingHref: _linkUrl(
        uri,
        _querySelector(document, '.comicParticulars-botton[href*="/chapter/"]'),
      ),
      chapterGroups: chapterGroups,
      chapters: _uniqueBy<ChapterData>(
        chapters,
        (ChapterData chapter) => chapter.href,
      ),
    );
  }

  DetailChapterRequest? _buildDetailChapterRequest(
    Uri uri,
    String html,
    dom.Document document,
  ) {
    final List<String> segments = uri.pathSegments;
    if (segments.length < 2 || segments.first != 'comic') {
      return null;
    }
    final String slug = _cleanText(segments[1]);
    final String dnt = _attr(document.querySelector('#dnt'), 'value');
    final String ccz = _cleanText(extractAssignedJavaScriptString(html, 'ccz'));
    if (slug.isEmpty || dnt.isEmpty || ccz.isEmpty) {
      return null;
    }
    return DetailChapterRequest(pageUri: uri, slug: slug, ccz: ccz, dnt: dnt);
  }

  List<String> parseEncryptedReaderImageUrls(
    Uri uri, {
    required String contentKey,
    required String cct,
  }) {
    final String encrypted = _cleanText(contentKey);
    if (encrypted.length <= 16) {
      throw SiteHtmlPageParseException('阅读页图片数据为空：${uri.path}');
    }

    final Uint8List plainBytes = _aesCbcDecrypt(
      keyMaterial: cct,
      encrypted: encrypted,
    );
    final Object? decoded = jsonDecode(utf8.decode(plainBytes));
    final List<String> imageUrls = _uniqueStrings(
      asObjectList(decoded).map((Object? item) {
        final String rawUrl = item is String
            ? _cleanText(item)
            : _stringValue(asStringKeyMap(item)['url']);
        if (rawUrl.isEmpty) {
          return '';
        }
        return AppConfig.resolveNavigationUri(
          rawUrl,
          currentUri: uri,
        ).toString();
      }),
    );
    if (imageUrls.isEmpty) {
      throw SiteHtmlPageParseException('阅读页图片数据格式异常：${uri.path}');
    }
    return imageUrls;
  }

  _ParsedDetailChapters _parseEncryptedDetailChapters(
    DetailChapterRequest request,
    String encryptedResults,
  ) {
    final String encrypted = _cleanText(encryptedResults);
    if (encrypted.length <= 16) {
      throw SiteHtmlPageParseException('详情页章节数据为空：${request.pageUri.path}');
    }

    final Uint8List plainBytes = _aesCbcDecrypt(
      keyMaterial: request.ccz,
      encrypted: encrypted,
    );
    final Object? decoded = jsonDecode(utf8.decode(plainBytes));
    if (decoded is! Map) {
      throw SiteHtmlPageParseException('详情页章节数据格式异常：${request.pageUri.path}');
    }

    final Map<String, Object?> payload = decoded.map(
      (Object? key, Object? value) => MapEntry(key.toString(), value),
    );
    final Map<String, Object?> build = asStringKeyMap(payload['build']);
    final String pathWord = _stringValue(build['path_word']).isNotEmpty
        ? _stringValue(build['path_word'])
        : request.slug;
    final Map<int, String> typeLabels = _chapterTypeLabels(build['type']);
    final List<Map<String, Object?>> groupMaps = _chapterGroupMaps(
      payload['groups'],
    );

    final List<ChapterGroupData> groups = groupMaps
        .map((Map<String, Object?> group) {
          final String groupName = _normalizeGroupName(
            _stringValue(group['name']),
            pathWord: _stringValue(group['path_word']),
          );
          final List<ChapterData> chapters = asObjectList(group['chapters'])
              .map(asStringKeyMap)
              .map((Map<String, Object?> chapter) {
                final String chapterId = _stringValue(chapter['id']);
                final String label = _stringValue(chapter['name']).isNotEmpty
                    ? _stringValue(chapter['name'])
                    : typeLabels[(chapter['type'] as num?)?.toInt() ?? 0] ??
                          '章节';
                if (chapterId.isEmpty || label.isEmpty) {
                  return null;
                }
                return ChapterData(
                  label: label,
                  href: AppConfig.resolvePath(
                    '/comic/$pathWord/chapter/$chapterId',
                  ).toString(),
                  subtitle: _stringValue(chapter['datetime_created']),
                );
              })
              .whereType<ChapterData>()
              .toList(growable: false);
          return ChapterGroupData(
            label: groupName,
            chapters: _uniqueBy<ChapterData>(
              chapters,
              (ChapterData chapter) => chapter.href,
            ),
          );
        })
        .where((ChapterGroupData group) => group.chapters.isNotEmpty)
        .toList(growable: false);

    final List<ChapterData> chapters = _uniqueBy<ChapterData>(
      groups.expand((ChapterGroupData group) => group.chapters),
      (ChapterData chapter) => chapter.href,
    );
    return _ParsedDetailChapters(chapterGroups: groups, chapters: chapters);
  }

  List<ChapterGroupData> _parseChapterGroupsFromDom(
    dom.Document document,
    Uri uri,
  ) {
    bool isLikelyChapterGroupLabel(String label) {
      final String normalized = _cleanText(label).replaceAll(' ', '');
      return normalized.isNotEmpty &&
          (normalized == '全部' ||
              normalized.contains('全部') ||
              normalized.contains('番外') ||
              normalized.contains('單話') ||
              normalized.contains('单话') ||
              normalized == '話' ||
              normalized.endsWith('話') ||
              normalized.contains('卷') ||
              normalized.contains('單行本') ||
              normalized.contains('单行本'));
    }

    String normalizeTarget(String value) {
      final String normalized = _cleanText(value);
      if (normalized.isEmpty) {
        return '';
      }
      if (normalized.startsWith('#')) {
        return normalized;
      }
      if (normalized.contains('/') ||
          normalized.contains(':') ||
          normalized.contains('?')) {
        return '';
      }
      return '#${normalized.replaceFirst(RegExp(r'^#'), '')}';
    }

    List<String> controlTargets(dom.Element node) {
      return _uniqueStrings(<String>[
        normalizeTarget(_attr(node, 'href')),
        normalizeTarget(_attr(node, 'data-target')),
        normalizeTarget(_attr(node, 'data-bs-target')),
        normalizeTarget(_attr(node, 'aria-controls')),
      ]).where((String item) => item.startsWith('#')).toList(growable: false);
    }

    final List<_ChapterGroupControl> controls = _uniqueBy<_ChapterGroupControl>(
      _querySelectorAll(
            document,
            '.nav-tabs a, .nav-tabs button, a[data-toggle="tab"], '
            'button[data-toggle="tab"], a[data-bs-toggle="tab"], '
            'button[data-bs-toggle="tab"], [role="tab"]',
          )
          .asMap()
          .entries
          .map((MapEntry<int, dom.Element> entry) {
            final dom.Element control = entry.value;
            return _ChapterGroupControl(
              label: _text(control).isNotEmpty
                  ? _text(control)
                  : '列表 ${entry.key + 1}',
              targets: controlTargets(control),
              index: entry.key,
            );
          })
          .where((control) {
            return control.targets.isNotEmpty ||
                isLikelyChapterGroupLabel(control.label);
          }),
      (_ChapterGroupControl control) =>
          '${control.label}::${control.targets.join('|')}',
    );

    final List<_ChapterGroupPane> panes =
        _querySelectorAll(document, '.tab-pane, .tab-content [role="tabpanel"]')
            .asMap()
            .entries
            .map((MapEntry<int, dom.Element> entry) {
              final dom.Element pane = entry.value;
              return _ChapterGroupPane(
                target: normalizeTarget(_attr(pane, 'id')),
                labelledBy: normalizeTarget(_attr(pane, 'aria-labelledby')),
                chapters: _collectChapterLinks(pane, uri),
                index: entry.key,
              );
            })
            .where((pane) {
              return pane.chapters.isNotEmpty ||
                  pane.target.isNotEmpty ||
                  pane.labelledBy.isNotEmpty;
            })
            .toList(growable: false);

    final Set<int> consumedPaneIndices = <int>{};
    final List<ChapterGroupData> groups = <ChapterGroupData>[];
    int sequentialPaneIndex = 0;

    for (final _ChapterGroupControl control in controls) {
      _ChapterGroupPane? pane = panes.cast<_ChapterGroupPane?>().firstWhere((
        _ChapterGroupPane? candidate,
      ) {
        return candidate != null &&
            control.targets.any((String target) {
              return target.isNotEmpty &&
                  (candidate.target == target ||
                      candidate.labelledBy == target);
            });
      }, orElse: () => null);
      if (pane == null && control.targets.isEmpty) {
        pane = panes.cast<_ChapterGroupPane?>().firstWhere((
          _ChapterGroupPane? candidate,
        ) {
          return candidate != null &&
              candidate.index >= sequentialPaneIndex &&
              !consumedPaneIndices.contains(candidate.index);
        }, orElse: () => null);
      }
      if (pane == null && !isLikelyChapterGroupLabel(control.label)) {
        continue;
      }
      if (pane != null) {
        consumedPaneIndices.add(pane.index);
        sequentialPaneIndex = pane.index + 1;
      }
      groups.add(
        ChapterGroupData(
          label: control.label,
          chapters: pane?.chapters ?? const <ChapterData>[],
        ),
      );
    }

    for (final _ChapterGroupPane pane in panes) {
      if (consumedPaneIndices.contains(pane.index) || pane.chapters.isEmpty) {
        continue;
      }
      groups.add(
        ChapterGroupData(
          label: '列表 ${pane.index + 1}',
          chapters: pane.chapters,
        ),
      );
    }

    return _uniqueBy<ChapterGroupData>(
      groups.where((ChapterGroupData group) {
        return group.label.isNotEmpty || group.chapters.isNotEmpty;
      }),
      (ChapterGroupData group) {
        final String firstHref = group.chapters.isEmpty
            ? ''
            : group.chapters.first.href;
        return '${_cleanText(group.label)}::$firstHref';
      },
    );
  }

  List<ComicCardData> _collectComicCards(
    Object root,
    Uri uri,
    String selector,
  ) {
    return _uniqueBy<ComicCardData>(
      _querySelectorAll(root, selector)
          .map((dom.Element anchor) => _buildComicCard(uri, anchor))
          .whereType<ComicCardData>(),
      (ComicCardData item) => item.href,
    );
  }

  ComicCardData? _buildComicCard(Uri uri, dom.Element anchor) {
    final dom.Element container =
        _findAncestorWithAnyClass(anchor, <String>[
          'exemptComic_Item',
          'dailyRecommendation-box',
          'col-auto',
          'topThree',
          'carousel-item',
        ]) ??
        _parentElement(anchor) ??
        anchor;
    final String title =
        _attr(_querySelector(container, '[title]'), 'title').isNotEmpty
        ? _attr(_querySelector(container, '[title]'), 'title')
        : _queryText(container, '.edit-txt').isNotEmpty
        ? _queryText(container, '.edit-txt')
        : _queryText(container, '.twoLines').isNotEmpty
        ? _queryText(container, '.twoLines')
        : _queryText(container, '.dailyRecommendation-txt').isNotEmpty
        ? _queryText(container, '.dailyRecommendation-txt')
        : _queryText(container, '.threeLines').isNotEmpty
        ? _queryText(container, '.threeLines')
        : _text(anchor);
    final String href = _linkUrl(uri, anchor);
    if (title.isEmpty || href.isEmpty) {
      return null;
    }
    return ComicCardData(
      title: title,
      subtitle: _queryText(container, '.exemptComicItem-txt-span').isNotEmpty
          ? _queryText(container, '.exemptComicItem-txt-span')
          : _queryText(container, '.dailyRecommendation-span').isNotEmpty
          ? _queryText(container, '.dailyRecommendation-span')
          : _queryText(container, '.oneLines'),
      secondaryText: _queryText(container, '.update span'),
      coverUrl: _imageUrl(uri, _querySelector(container, 'img')),
      href: href,
    );
  }

  List<ComicCardData> _discoverItemsFromInlineList(
    Uri uri,
    dom.Document document,
  ) {
    final String rawList = _attr(
      _querySelector(document, '.exemptComicList .exemptComic-box'),
      'list',
    );
    if (rawList.isEmpty) {
      return const <ComicCardData>[];
    }

    final Object? decoded;
    try {
      decoded = parseJavaScriptLiteral(rawList);
    } on FormatException {
      return const <ComicCardData>[];
    }
    if (decoded is! List) {
      return const <ComicCardData>[];
    }

    return decoded
        .whereType<Map>()
        .map(asStringKeyMap)
        .map((Map<String, Object?> item) {
          final String pathWord = _stringValue(item['path_word']);
          final String title = _stringValue(item['name']);
          if (pathWord.isEmpty || title.isEmpty) {
            return null;
          }

          final List<Map<String, Object?>> authors = asObjectList(
            item['author'],
          ).whereType<Map>().map(asStringKeyMap).toList(growable: false);
          final List<String> authorNames = authors
              .map(
                (Map<String, Object?> author) => _stringValue(author['name']),
              )
              .where((String value) => value.isNotEmpty)
              .toList(growable: false);
          final String subtitle = authorNames.isEmpty
              ? '作者：--'
              : authorNames.length == 1
              ? '作者：${authorNames.first}'
              : '作者：${authorNames.first} 等${authorNames.length}位';

          return ComicCardData(
            title: title,
            subtitle: subtitle,
            coverUrl: _stringValue(item['cover']),
            href: AppConfig.resolvePath('/comic/$pathWord').toString(),
          );
        })
        .whereType<ComicCardData>()
        .toList(growable: false);
  }
}

class _ParsedDetailChapters {
  const _ParsedDetailChapters({
    required this.chapterGroups,
    required this.chapters,
  });

  final List<ChapterGroupData> chapterGroups;
  final List<ChapterData> chapters;
}

class _ChapterGroupControl {
  const _ChapterGroupControl({
    required this.label,
    required this.targets,
    required this.index,
  });

  final String label;
  final List<String> targets;
  final int index;
}

class _ChapterGroupPane {
  const _ChapterGroupPane({
    required this.target,
    required this.labelledBy,
    required this.chapters,
    required this.index,
  });

  final String target;
  final String labelledBy;
  final List<ChapterData> chapters;
  final int index;
}
