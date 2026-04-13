import 'dart:convert';
import 'dart:typed_data';

import 'package:easy_copy/config/app_config.dart';
import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/services/js_literal_utils.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:pointycastle/export.dart';

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

class SiteHtmlPageParser {
  const SiteHtmlPageParser();

  static const SiteHtmlPageParser instance = SiteHtmlPageParser();

  static final RegExp _spacePattern = RegExp(r'\s+');
  static final RegExp _hexPattern = RegExp(r'^[0-9a-fA-F]+$');

  Future<EasyCopyPage> parsePage(
    Uri uri,
    String html, {
    DetailChapterResultsLoader? loadDetailChapterResults,
  }) async {
    final Uri normalizedUri = AppConfig.rewriteToCurrentHost(uri);
    final dom.Document document = html_parser.parse(html);
    final EasyCopyPageType pageType = _detectPageType(normalizedUri, document);

    switch (pageType) {
      case EasyCopyPageType.home:
        return _buildHomePage(normalizedUri, document);
      case EasyCopyPageType.discover:
        return _buildDiscoverPage(normalizedUri, document);
      case EasyCopyPageType.rank:
        return _buildRankPage(normalizedUri, document);
      case EasyCopyPageType.detail:
        return _buildDetailPage(
          normalizedUri,
          html,
          document,
          loadDetailChapterResults: loadDetailChapterResults,
        );
      case EasyCopyPageType.reader:
        return _buildReaderPage(normalizedUri, html, document);
      case EasyCopyPageType.profile:
      case EasyCopyPageType.unknown:
        throw SiteHtmlPageParseException(
          '当前 HTML loader 不支持解析此页面：${normalizedUri.path}',
        );
    }
  }

  EasyCopyPageType _detectPageType(Uri uri, dom.Document document) {
    final String path = uri.path.toLowerCase();
    if (path.contains('/chapter/')) {
      return EasyCopyPageType.reader;
    }
    if (document.querySelector('.comicParticulars-title') != null) {
      return EasyCopyPageType.detail;
    }
    if (document.querySelector('.ranking-box') != null) {
      return EasyCopyPageType.rank;
    }
    if (document.querySelector('.exemptComicList') != null ||
        document.querySelector('.correlationList .exemptComic_Item') != null ||
        document.querySelector('.specialDetail') != null ||
        document.querySelector('.specialContent') != null ||
        path.startsWith('/comics') ||
        path.startsWith('/filter') ||
        path.startsWith('/topic') ||
        path.startsWith('/recommend') ||
        path.startsWith('/newest') ||
        path.startsWith('/author') ||
        path.startsWith('/search')) {
      return EasyCopyPageType.discover;
    }
    if (document.querySelector('.content-box .swiperList') != null ||
        document.querySelector('.comicRank') != null ||
        path == '/') {
      return EasyCopyPageType.home;
    }
    if (path.startsWith('/web/login') || path.startsWith('/person')) {
      return EasyCopyPageType.profile;
    }
    return EasyCopyPageType.unknown;
  }

  HomePageData _buildHomePage(Uri uri, dom.Document document) {
    final List<ComicSectionData>
    sections = _querySelectorAll(document, '.index-all-icon')
        .map((dom.Element header) {
          final String title = _queryText(header, '.index-all-icon-left-txt');
          final String sectionHref = _linkUrl(
            uri,
            _querySelector(header, '.index-all-icon-right a'),
          );
          final Uri? sectionUri = Uri.tryParse(sectionHref);
          final String normalizedTitle = title.replaceAll(RegExp(r'\s+'), '');
          final String normalizedSectionPath = (sectionUri?.path ?? sectionHref)
              .trim()
              .toLowerCase();
          if (title.isEmpty || title.contains('排行榜')) {
            return null;
          }
          if (normalizedTitle.contains('熱門更新') ||
              normalizedTitle.contains('热门更新') ||
              normalizedSectionPath == '/comics' ||
              normalizedSectionPath == '/comics/') {
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

    final dom.Element? featureBlock = _querySelector(document, '.special');
    final dom.Element? featureAnchor = featureBlock == null
        ? null
        : _parentElement(featureBlock);
    final HeroBannerData? feature =
        featureBlock == null || featureAnchor == null
        ? null
        : HeroBannerData(
            title: _queryText(featureBlock, '.special-text-h4 p'),
            subtitle: _queryText(featureBlock, '.special-time'),
            imageUrl: _imageUrl(uri, _querySelector(featureBlock, 'img')),
            href: _linkUrl(uri, featureAnchor),
          );

    return HomePageData(
      title: '首頁',
      uri: uri.toString(),
      heroBanners: const <HeroBannerData>[],
      sections: sections,
      feature: feature == null || feature.title.isEmpty || feature.href.isEmpty
          ? null
          : feature,
    );
  }

  DiscoverPageData _buildDiscoverPage(Uri uri, dom.Document document) {
    final String path = uri.path.toLowerCase();
    final bool isTopicDetail =
        path.startsWith('/topic/') ||
        document.querySelector('.specialDetail') != null;
    final bool isTopicRoute = path.startsWith('/topic');
    List<ComicCardData> items = isTopicDetail
        ? _collectTopicDetailComicCards(document, uri)
        : isTopicRoute
        ? _collectTopicListCards(document, uri)
        : _collectComicCards(
            document,
            uri,
            '.exemptComic-box a[href*="/comic/"], '
            '.correlationList a[href*="/comic/"]',
          );
    if (items.isEmpty && !isTopicRoute) {
      items = _discoverItemsFromInlineList(uri, document);
    }
    final dom.Element? pager = document.querySelector('.page-all');
    final List<dom.Element> totalLabels = pager == null
        ? const <dom.Element>[]
        : pager.querySelectorAll('.page-total').toList(growable: false);

    return DiscoverPageData(
      title: _pageTitle(document),
      uri: uri.toString(),
      filters: isTopicRoute
          ? const <FilterGroupData>[]
          : _collectFilterGroups(document, uri),
      items: items,
      pager: PagerData(
        currentLabel: _queryText(pager, '.page-all-item.active a'),
        totalLabel: totalLabels.isEmpty ? '' : _text(totalLabels.last),
        prevHref: _linkUrl(uri, _querySelector(pager, '.prev a, .prev-all a')),
        nextHref: _linkUrl(uri, _querySelector(pager, '.next a, .next-all a')),
      ),
      spotlight: isTopicRoute
          ? const <ComicCardData>[]
          : _collectComicCards(
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
        imageUrls = _parseEncryptedReaderImageUrls(
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
    final String comicId = extractJavaScriptCallStringArgument(
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
      chapterGroups = _parseDetailChapterGroupsFromDom(document, uri);
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

  List<String> _parseEncryptedReaderImageUrls(
    Uri uri, {
    required String contentKey,
    required String cct,
  }) {
    final String encrypted = _cleanText(contentKey);
    if (encrypted.length <= 16) {
      throw SiteHtmlPageParseException('阅读页图片数据为空：${uri.path}');
    }

    final Uint8List key = Uint8List.fromList(utf8.encode(cct));
    final Uint8List iv = Uint8List.fromList(
      utf8.encode(encrypted.substring(0, 16)),
    );
    final Uint8List cipherBytes = _decodeCipherText(encrypted.substring(16));
    final PaddedBlockCipher cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      CBCBlockCipher(AESEngine()),
    );
    cipher.init(
      false,
      PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
        ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
        null,
      ),
    );

    final Uint8List plainBytes = cipher.process(cipherBytes);
    final Object? decoded = jsonDecode(utf8.decode(plainBytes));
    final List<String> imageUrls = _uniqueStrings(
      _listValue(decoded).map((Object? item) {
        final String rawUrl = item is String
            ? _cleanText(item)
            : _stringValue(_asMap(item)['url']);
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

    final Uint8List key = Uint8List.fromList(utf8.encode(request.ccz));
    final Uint8List iv = Uint8List.fromList(
      utf8.encode(encrypted.substring(0, 16)),
    );
    final Uint8List cipherBytes = _decodeCipherText(encrypted.substring(16));
    final PaddedBlockCipher cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      CBCBlockCipher(AESEngine()),
    );
    cipher.init(
      false,
      PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
        ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
        null,
      ),
    );

    final Uint8List plainBytes = cipher.process(cipherBytes);
    final Object? decoded = jsonDecode(utf8.decode(plainBytes));
    if (decoded is! Map) {
      throw SiteHtmlPageParseException('详情页章节数据格式异常：${request.pageUri.path}');
    }

    final Map<String, Object?> payload = decoded.map(
      (Object? key, Object? value) => MapEntry(key.toString(), value),
    );
    final Map<String, Object?> build = _asMap(payload['build']);
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
          final List<ChapterData> chapters = _listValue(group['chapters'])
              .map(_asMap)
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

  List<ChapterGroupData> _parseDetailChapterGroupsFromDom(
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
      secondaryText: _queryText(container, '.update span').isNotEmpty
          ? _queryText(container, '.update span')
          : _queryText(container, '.special-time'),
      coverUrl: _imageUrl(uri, _querySelector(container, 'img')),
      href: href,
      badge: _queryText(container, '.special-text span'),
    );
  }

  List<ComicCardData> _collectTopicListCards(Object root, Uri uri) {
    return _uniqueBy<ComicCardData>(
      _querySelectorAll(root, '.specialContent').map((dom.Element card) {
        final dom.Element? anchor =
            _querySelector(card, '.specialContentImage a[href]') ??
            _querySelector(card, '.specialContentButton a[href]');
        final String href = _linkUrl(uri, anchor);
        final String title =
            _queryText(card, '.specialContentImageSpan').isNotEmpty
            ? _queryText(card, '.specialContentImageSpan')
            : _queryText(card, '.specialContentTextTitle').isNotEmpty
            ? _queryText(card, '.specialContentTextTitle')
            : _text(anchor);
        if (title.isEmpty || href.isEmpty) {
          return null;
        }
        return ComicCardData(
          title: title,
          subtitle: _queryText(card, '.specialContentTextContent'),
          secondaryText: _queryText(card, '.specialContentButtonTime'),
          coverUrl: _imageUrl(
            uri,
            _querySelector(card, '.specialContentImage img'),
          ),
          href: href,
          badge: '專題',
        );
      }).whereType<ComicCardData>(),
      (ComicCardData item) => item.href,
    );
  }

  List<ComicCardData> _collectTopicDetailComicCards(Object root, Uri uri) {
    return _uniqueBy<ComicCardData>(
      _querySelectorAll(root, '.specialDetailItem').map((dom.Element card) {
        final dom.Element? titleAnchor =
            _querySelector(
              card,
              '.specialDetailItemHeaderContentName a[href]',
            ) ??
            _querySelector(card, '.specialDetailItemHeaderImage a[href]');
        final String href = _linkUrl(uri, titleAnchor);
        final String title = _text(titleAnchor);
        if (title.isEmpty || href.isEmpty) {
          return null;
        }

        final List<String> authorLabels = _uniqueStrings(
          _querySelectorAll(
            card,
            '.specialDetailItemHeaderContentText a[href*="/author/"]',
          ).map(_text),
        );
        final List<String> infoLines =
            _querySelectorAll(card, '.specialDetailItemHeaderContentText')
                .map(_text)
                .where((String item) => item.isNotEmpty)
                .toList(growable: false);
        final String heatLine = infoLines.firstWhere(
          (String value) => value.contains('熱度') || value.contains('热度'),
          orElse: () => '',
        );
        final List<String> tagLabels = _uniqueStrings(
          _querySelectorAll(card, '.specialDetailItemHeaderContentLabel a').map(
            (dom.Element anchor) =>
                _text(anchor).replaceFirst(RegExp(r'^#'), ''),
          ),
        );

        return ComicCardData(
          title: title,
          subtitle: authorLabels.isEmpty
              ? ''
              : '作者：${authorLabels.join(' / ')}',
          secondaryText: heatLine,
          coverUrl: _imageUrl(
            uri,
            _querySelector(card, '.specialDetailItemHeaderImage img'),
          ),
          href: href,
          badge: tagLabels.isEmpty ? '' : tagLabels.first,
        );
      }).whereType<ComicCardData>(),
      (ComicCardData item) => item.href,
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
        .map(_asMap)
        .map((Map<String, Object?> item) {
          final String pathWord = _stringValue(item['path_word']);
          final String title = _stringValue(item['name']);
          if (pathWord.isEmpty || title.isEmpty) {
            return null;
          }

          final List<Map<String, Object?>> authors = _listValue(
            item['author'],
          ).whereType<Map>().map(_asMap).toList(growable: false);
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

  List<FilterGroupData> _collectFilterGroups(dom.Document document, Uri uri) {
    return _querySelectorAll(document, '.classify-txt-all')
        .map((dom.Element group) {
          final String label = _text(
            _querySelector(group, 'dt'),
          ).replaceAll('：', '').replaceAll(':', '');
          final List<LinkAction> options =
              _querySelectorAll(group, '.classify-right a')
                  .map((dom.Element anchor) {
                    final String optionLabel =
                        _queryText(anchor, 'dd').isNotEmpty
                        ? _queryText(anchor, 'dd')
                        : _text(anchor);
                    final String href = _linkUrl(uri, anchor);
                    if (optionLabel.isEmpty || href.isEmpty) {
                      return null;
                    }
                    return LinkAction(
                      label: optionLabel,
                      href: href,
                      active: anchor.querySelector('.active') != null,
                    );
                  })
                  .whereType<LinkAction>()
                  .toList(growable: false);
          if (label.isEmpty || options.isEmpty) {
            return null;
          }
          return FilterGroupData(label: label, options: options);
        })
        .whereType<FilterGroupData>()
        .toList(growable: false);
  }

  List<ChapterData> _collectChapterLinks(Object root, Uri uri) {
    return _uniqueBy<ChapterData>(
      _querySelectorAll(root, 'a[href*="/chapter/"]').map((dom.Element anchor) {
        final String label = _text(anchor);
        final String href = _linkUrl(uri, anchor);
        if (label.isEmpty ||
            href.isEmpty ||
            label.contains('開始閱讀') ||
            label.contains('开始阅读')) {
          return null;
        }
        return ChapterData(label: label, href: href);
      }).whereType<ChapterData>(),
      (ChapterData chapter) => chapter.href,
    );
  }

  List<String> _collectReaderImageUrlsFromDom(dom.Document document, Uri uri) {
    return _uniqueStrings(
      _querySelectorAll(document, '.comicContent-list img').map((
        dom.Element img,
      ) {
        return _imageUrl(uri, img);
      }),
    );
  }

  Map<int, String> _chapterTypeLabels(Object? rawTypes) {
    final Map<int, String> labels = <int, String>{1: '話', 2: '卷', 3: '番外篇'};
    for (final Object? item in _listValue(rawTypes)) {
      final Map<String, Object?> map = _asMap(item);
      final int? id = (map['id'] as num?)?.toInt();
      final String name = _stringValue(map['name']);
      if (id != null && name.isNotEmpty) {
        labels[id] = name;
      }
    }
    return labels;
  }

  List<Map<String, Object?>> _chapterGroupMaps(Object? rawGroups) {
    if (rawGroups is Map) {
      return rawGroups.values
          .whereType<Map>()
          .map(_asMap)
          .toList(growable: false);
    }
    if (rawGroups is List) {
      return rawGroups.whereType<Map>().map(_asMap).toList(growable: false);
    }
    return const <Map<String, Object?>>[];
  }

  String _normalizeGroupName(String name, {required String pathWord}) {
    final String normalized = _cleanText(name);
    if (normalized.isEmpty ||
        normalized == '默認' ||
        normalized == '默认' ||
        normalized.toLowerCase() == 'default' ||
        normalized == pathWord) {
      return '全部';
    }
    return normalized;
  }

  Uint8List _decodeCipherText(String payload) {
    final String normalized = _cleanText(payload);
    if (_hexPattern.hasMatch(normalized) && normalized.length.isEven) {
      return Uint8List.fromList(_hexDecode(normalized));
    }
    return Uint8List.fromList(base64Decode(normalized));
  }

  List<int> _hexDecode(String value) {
    final List<int> bytes = <int>[];
    for (int index = 0; index < value.length; index += 2) {
      bytes.add(int.parse(value.substring(index, index + 2), radix: 16));
    }
    return bytes;
  }

  Map<String, Object?> _asMap(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return value.map(
        (Object? key, Object? nested) => MapEntry(key.toString(), nested),
      );
    }
    return const <String, Object?>{};
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

  String _stringValue(Object? value) {
    return value is String ? _cleanText(value) : '';
  }

  List<T> _uniqueBy<T>(Iterable<T> items, String Function(T item) keyFactory) {
    final Set<String> seen = <String>{};
    final List<T> unique = <T>[];
    for (final T item in items) {
      final String key = keyFactory(item);
      if (key.isEmpty || !seen.add(key)) {
        continue;
      }
      unique.add(item);
    }
    return unique;
  }

  List<String> _uniqueStrings(Iterable<String> items) {
    final Set<String> seen = <String>{};
    final List<String> unique = <String>[];
    for (final String item in items.map(_cleanText)) {
      if (item.isEmpty || !seen.add(item)) {
        continue;
      }
      unique.add(item);
    }
    return unique;
  }

  String _cleanText(String? value) {
    return (value ?? '').replaceAll(_spacePattern, ' ').trim();
  }

  String _scriptStringValue(String html, String variableName) {
    return _cleanText(extractAssignedJavaScriptString(html, variableName));
  }

  String _pageTitle(dom.Document document) {
    final String title = _cleanText(document.querySelector('title')?.text);
    if (title.isEmpty) {
      return 'EasyCopy';
    }
    return title.replaceFirst(RegExp(r'\s*-\s*拷[^-]+$'), '');
  }

  String _attr(dom.Element? node, String name) {
    return _cleanText(node?.attributes[name]);
  }

  String _text(dom.Node? node) {
    return _cleanText(node?.text);
  }

  String _queryText(Object? root, String selector) {
    return _text(_querySelector(root, selector));
  }

  dom.Element? _querySelector(Object? root, String selector) {
    if (root is dom.Document) {
      return root.querySelector(selector);
    }
    if (root is dom.Element) {
      return root.querySelector(selector);
    }
    return null;
  }

  List<dom.Element> _querySelectorAll(Object? root, String selector) {
    if (root is dom.Document) {
      return root.querySelectorAll(selector).toList(growable: false);
    }
    if (root is dom.Element) {
      return root.querySelectorAll(selector).toList(growable: false);
    }
    return const <dom.Element>[];
  }

  dom.Element? _parentElement(dom.Element element) {
    final dom.Node? parent = element.parent;
    return parent is dom.Element ? parent : null;
  }

  dom.Element? _findAncestorWithAnyClass(
    dom.Element element,
    List<String> classes,
  ) {
    dom.Element? current = element;
    while (current != null) {
      final bool matches = classes.any(current.classes.contains);
      if (matches) {
        return current;
      }
      current = _parentElement(current);
    }
    return null;
  }

  String _imageUrl(Uri currentUri, dom.Element? node) {
    if (node == null) {
      return '';
    }
    final String source = _attr(node, 'data-src').isNotEmpty
        ? _attr(node, 'data-src')
        : _attr(node, 'data-original').isNotEmpty
        ? _attr(node, 'data-original')
        : _attr(node, 'data').isNotEmpty
        ? _attr(node, 'data')
        : _cleanText(node.attributes['src']);
    if (source.isEmpty || source == '#') {
      return '';
    }
    return AppConfig.resolveNavigationUri(
      source,
      currentUri: currentUri,
    ).toString();
  }

  String _linkUrl(Uri currentUri, dom.Element? node) {
    final String href = _attr(node, 'href');
    if (href.isEmpty || href == '#') {
      return '';
    }
    return AppConfig.resolveNavigationUri(
      href,
      currentUri: currentUri,
    ).toString();
  }

  String _infoValue(List<dom.Element> infoRows, String prefix) {
    final dom.Element? row = _rowByPrefix(infoRows, prefix);
    if (row == null) {
      return '';
    }

    final dom.Element valueNode =
        _querySelector(row, '.comicParticulars-right-txt') ??
        _querySelector(row, 'p') ??
        (row.querySelectorAll('span').length > 1
            ? row.querySelectorAll('span')[1]
            : null) ??
        row;
    final String fullText = _text(valueNode).isNotEmpty
        ? _text(valueNode)
        : _text(row);
    return _cleanText(
      fullText.replaceAll('$prefix：', '').replaceAll('$prefix:', ''),
    );
  }

  dom.Element? _rowByPrefix(List<dom.Element> rows, String prefix) {
    for (final dom.Element row in rows) {
      final String label = _text(_querySelector(row, 'span'));
      if (label.startsWith(prefix)) {
        return row;
      }
    }
    return null;
  }

  List<String> _mapText(Iterable<String> items) {
    return items
        .map(_cleanText)
        .where((String value) => value.isNotEmpty)
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
