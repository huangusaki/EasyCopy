import 'dart:convert';

import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/services/host_manager.dart';
import 'package:easy_copy/services/js_literal_utils.dart';
import 'package:http/http.dart' as http;
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

typedef ProbeNowProvider = DateTime Function();

class PageProbeResult {
  const PageProbeResult({
    required this.uri,
    required this.pageType,
    required this.fingerprint,
    required this.fetchedAt,
  });

  final Uri uri;
  final EasyCopyPageType pageType;
  final String fingerprint;
  final DateTime fetchedAt;
}

class PageProbeService {
  PageProbeService({
    http.Client? client,
    ProbeNowProvider? now,
    required this.userAgent,
  }) : _client = client ?? http.Client(),
       _now = now ?? DateTime.now;

  static final PageProbeService instance = PageProbeService(
    userAgent: defaultDesktopUserAgent,
  );

  final http.Client _client;
  final ProbeNowProvider _now;
  final String userAgent;

  Future<PageProbeResult> probe(Uri uri) async {
    final http.Response response = await _client.get(
      uri,
      headers: <String, String>{'User-Agent': userAgent},
    );
    final String body = utf8.decode(response.bodyBytes);
    final dom.Document document = html_parser.parse(body);
    final EasyCopyPageType pageType = _detectPageType(uri, document);
    return PageProbeResult(
      uri: uri,
      pageType: pageType,
      fingerprint: _buildFingerprint(uri, body, document, pageType),
      fetchedAt: _now(),
    );
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
        path.startsWith('/search') ||
        path.startsWith('/comics') ||
        path.startsWith('/topic') ||
        path.startsWith('/recommend') ||
        path.startsWith('/newest')) {
      return EasyCopyPageType.discover;
    }
    if (document.querySelector('.content-box .swiperList') != null ||
        document.querySelector('.comicRank') != null ||
        path == '/') {
      return EasyCopyPageType.home;
    }
    return EasyCopyPageType.unknown;
  }

  String _buildFingerprint(
    Uri uri,
    String body,
    dom.Document document,
    EasyCopyPageType pageType,
  ) {
    switch (pageType) {
      case EasyCopyPageType.detail:
        return _detailFingerprint(uri, document);
      case EasyCopyPageType.reader:
        return _readerFingerprint(uri, body, document);
      case EasyCopyPageType.rank:
        return _rankFingerprint(uri, document);
      case EasyCopyPageType.discover:
        if (uri.path.toLowerCase().startsWith('/topic')) {
          return _topicFingerprint(uri, document);
        }
        return _listFingerprint(uri, document);
      case EasyCopyPageType.home:
      case EasyCopyPageType.profile:
      case EasyCopyPageType.unknown:
        return _listFingerprint(uri, document);
    }
  }

  String _listFingerprint(Uri uri, dom.Document document) {
    final List<String> activeFilters = document
        .querySelectorAll('.active, .page-all-item.active a')
        .map(_nodeText)
        .where((String value) => value.isNotEmpty)
        .toList(growable: false);
    final List<_CardFingerprint> cards = _comicCards(document, uri);
    final _CardFingerprint? first = cards.isEmpty ? null : cards.first;
    final _CardFingerprint? last = cards.isEmpty ? null : cards.last;
    return <String>[
      uri.path,
      uri.query,
      activeFilters.join('|'),
      first?.fingerprint ?? '',
      last?.fingerprint ?? '',
      '${cards.length}',
    ].join('::');
  }

  String _rankFingerprint(Uri uri, dom.Document document) {
    final List<String> activeTabs = document
        .querySelectorAll('.rankingTime a.active, .active')
        .map(_nodeText)
        .where((String value) => value.isNotEmpty)
        .toList(growable: false);
    final List<_CardFingerprint> cards = _comicCards(
      document,
      uri,
      selector: '.ranking-all-box a[href*="/comic/"]',
    );
    return <String>[
      uri.path,
      activeTabs.join('|'),
      cards.isEmpty ? '' : cards.first.fingerprint,
      cards.isEmpty ? '' : cards.last.fingerprint,
      '${cards.length}',
    ].join('::');
  }

  String _topicFingerprint(Uri uri, dom.Document document) {
    final String path = uri.path.toLowerCase();
    if (path.startsWith('/topic/') ||
        document.querySelector('.specialDetail') != null) {
      final List<_CardFingerprint> cards = _topicDetailCards(document, uri);
      return <String>[
        uri.path,
        _nodeText(document.querySelector('.specialDetailTitleFlex span')),
        cards.isEmpty ? '' : cards.first.fingerprint,
        cards.isEmpty ? '' : cards.last.fingerprint,
        '${cards.length}',
      ].join('::');
    }

    final List<_CardFingerprint> cards = _topicCards(document, uri);
    return <String>[
      uri.path,
      uri.query,
      _nodeText(document.querySelector('.page-all-item.active a')),
      cards.isEmpty ? '' : cards.first.fingerprint,
      cards.isEmpty ? '' : cards.last.fingerprint,
      '${cards.length}',
    ].join('::');
  }

  String _detailFingerprint(Uri uri, dom.Document document) {
    final String updatedAt = _infoValue(document, '最後更新');
    final String status = _infoValue(document, '狀態');
    final List<String> chapterLinks = document
        .querySelectorAll('a[href*="/chapter/"]')
        .map(
          (dom.Element anchor) => _absoluteUrl(uri, anchor.attributes['href']),
        )
        .where((String value) => value.isNotEmpty)
        .toList(growable: false);
    final String firstChapter = chapterLinks.isEmpty ? '' : chapterLinks.first;
    final String lastChapter = chapterLinks.isEmpty ? '' : chapterLinks.last;
    return <String>[
      uri.path,
      updatedAt,
      status,
      '${chapterLinks.length}',
      firstChapter,
      lastChapter,
    ].join('::');
  }

  String _readerFingerprint(Uri uri, String body, dom.Document document) {
    final String title = _nodeText(document.querySelector('h4.header'));
    final String progress = _nodeText(
      document.querySelector('.comicContent-footer-txt span'),
    );
    final String contentKey = extractAssignedJavaScriptString(
      body,
      'contentKey',
    );
    return <String>[uri.path, title, progress, contentKey].join('::');
  }

  List<_CardFingerprint> _comicCards(
    dom.Document document,
    Uri currentUri, {
    String selector = 'a[href*="/comic/"]',
  }) {
    return document
        .querySelectorAll(selector)
        .map((dom.Element anchor) {
          final dom.Element container =
              anchor.parent?.parent ?? anchor.parent ?? anchor;
          final String containerTitle = _nodeText(
            container.querySelector('[title]'),
          );
          final String title =
              (anchor.attributes['title']?.trim() ?? '').isNotEmpty
              ? anchor.attributes['title']!.trim()
              : (containerTitle.isNotEmpty
                    ? containerTitle
                    : _nodeText(anchor));
          final String href = _absoluteUrl(
            currentUri,
            anchor.attributes['href'],
          );
          if (title.isEmpty && href.isEmpty) {
            return null;
          }
          return _CardFingerprint(title: title, href: href);
        })
        .whereType<_CardFingerprint>()
        .toList(growable: false);
  }

  List<_CardFingerprint> _topicCards(dom.Document document, Uri currentUri) {
    final Map<String, _CardFingerprint> cards = <String, _CardFingerprint>{};
    for (final dom.Element card in document.querySelectorAll(
      '.specialContent',
    )) {
      final dom.Element? anchor =
          card.querySelector('.specialContentImage a[href*="/topic/"]') ??
          card.querySelector('.specialContentButton a[href*="/topic/"]');
      if (anchor == null) {
        continue;
      }
      final String href = _absoluteUrl(currentUri, anchor.attributes['href']);
      if (href.isEmpty || cards.containsKey(href)) {
        continue;
      }
      final String title =
          _nodeText(card.querySelector('.specialContentImageSpan')).isNotEmpty
          ? _nodeText(card.querySelector('.specialContentImageSpan'))
          : (_nodeText(
                  card.querySelector('.specialContentTextTitle'),
                ).isNotEmpty
                ? _nodeText(card.querySelector('.specialContentTextTitle'))
                : _nodeText(anchor));
      cards[href] = _CardFingerprint(title: title, href: href);
    }
    return cards.values.toList(growable: false);
  }

  List<_CardFingerprint> _topicDetailCards(
    dom.Document document,
    Uri currentUri,
  ) {
    final Map<String, _CardFingerprint> cards = <String, _CardFingerprint>{};
    for (final dom.Element card in document.querySelectorAll(
      '.specialDetailItem',
    )) {
      final dom.Element? anchor =
          card.querySelector(
            '.specialDetailItemHeaderContentName a[href*="/comic/"]',
          ) ??
          card.querySelector(
            '.specialDetailItemHeaderImage a[href*="/comic/"]',
          );
      if (anchor == null) {
        continue;
      }
      final String href = _absoluteUrl(currentUri, anchor.attributes['href']);
      if (href.isEmpty || cards.containsKey(href)) {
        continue;
      }
      final String title =
          _nodeText(
            card.querySelector('.specialDetailItemHeaderContentName a'),
          ).isNotEmpty
          ? _nodeText(
              card.querySelector('.specialDetailItemHeaderContentName a'),
            )
          : _nodeText(anchor);
      cards[href] = _CardFingerprint(title: title, href: href);
    }
    return cards.values.toList(growable: false);
  }

  String _infoValue(dom.Document document, String prefix) {
    for (final dom.Element row in document.querySelectorAll(
      '.comicParticulars-title-right li',
    )) {
      final String label = _nodeText(row.querySelector('span'));
      if (!label.startsWith(prefix)) {
        continue;
      }
      final String rawText = _nodeText(row);
      return rawText
          .replaceAll('$prefix：', '')
          .replaceAll('$prefix:', '')
          .trim();
    }
    return '';
  }

  String _nodeText(dom.Element? node) {
    return node?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
  }

  String _absoluteUrl(Uri currentUri, String? href) {
    final String nextHref = (href ?? '').trim();
    if (nextHref.isEmpty || nextHref == '#') {
      return '';
    }
    return currentUri.resolve(nextHref).toString();
  }
}

class _CardFingerprint {
  const _CardFingerprint({required this.title, required this.href});

  final String title;
  final String href;

  String get fingerprint => '$title::$href';
}
