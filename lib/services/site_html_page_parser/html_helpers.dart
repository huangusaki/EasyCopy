part of '../site_html_page_parser.dart';

extension _SiteHtmlHelpers on SiteHtmlPageParser {
  bool _isHotSiteUri(Uri uri) {
    return uri.host.trim().toLowerCase().contains('manga2026');
  }

  bool _isHotPaidHomeSection(
    Uri uri, {
    required String title,
    required String href,
  }) {
    if (!_isHotSiteUri(uri)) {
      return false;
    }
    final String normalizedTitle = title.replaceAll(RegExp(r'\s+'), '');
    if (!normalizedTitle.contains('付費漫畫') &&
        !normalizedTitle.contains('付费漫画')) {
      return false;
    }
    final Uri? hrefUri = Uri.tryParse(href.trim());
    final String path = (hrefUri?.path ?? href).trim().toLowerCase();
    return path == '/comics' &&
        (hrefUri?.queryParameters['type'] == '2' ||
            href.toLowerCase().contains('type=2'));
  }

  dom.Element? _homeSectionItemsRoot(dom.Element header) {
    final dom.Element? container = _parentElement(header);
    if (container == null) {
      return null;
    }
    final int headerIndex = container.children.indexOf(header);
    if (headerIndex < 0) {
      return null;
    }

    for (final dom.Element sibling in container.children.skip(
      headerIndex + 1,
    )) {
      if (sibling.classes.contains('row')) {
        return sibling;
      }
      final dom.Element? nestedRow = _querySelector(sibling, '.row');
      if (nestedRow != null) {
        return nestedRow;
      }
    }
    return null;
  }

  List<Object> _rankEntryScopes(Uri uri, dom.Document document) {
    if (!_isHotSiteUri(uri)) {
      return <Object>[document];
    }
    final List<dom.Element> comicBlocks = _querySelectorAll(
      document,
      '.ranking-item',
    ).where(_isHotComicRankBlock).toList(growable: false);
    return comicBlocks.isEmpty ? <Object>[document] : comicBlocks;
  }

  bool _isHotComicRankBlock(dom.Element block) {
    final String normalizedTitle = _queryText(
      block,
      '.theBoxModel',
    ).replaceAll(RegExp(r'\s+'), '');
    if (normalizedTitle.contains('動畫') ||
        normalizedTitle.contains('动画') ||
        block.classes.contains('cartoon')) {
      return false;
    }
    if (normalizedTitle.contains('漫畫榜') ||
        normalizedTitle.contains('漫画榜') ||
        normalizedTitle.contains('免費漫畫') ||
        normalizedTitle.contains('免费漫画') ||
        normalizedTitle.contains('付費漫畫') ||
        normalizedTitle.contains('付费漫画') ||
        block.classes.contains('free') ||
        block.classes.contains('pay')) {
      return true;
    }
    return _querySelector(block, 'a[href*="/comic/"]') != null &&
        _querySelector(block, 'a[href*="/cartoon/"]') == null;
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

  List<FilterGroupData> _withHotComicTypeFilter(
    Uri uri,
    List<FilterGroupData> groups,
  ) {
    if (!_isHotComicsUri(uri)) {
      return groups;
    }
    final List<FilterGroupData> normalizedGroups = groups
        .where((FilterGroupData group) => group.label.trim() != '类型')
        .toList(growable: false);
    return <FilterGroupData>[
      FilterGroupData(
        label: '类型',
        options: <LinkAction>[
          LinkAction(
            label: '免费漫画',
            href: _hotComicTypeHref(uri, normalizedGroups, '1'),
            active: uri.queryParameters['type'] != '2',
          ),
          LinkAction(
            label: '付费漫画',
            href: _hotComicTypeHref(uri, normalizedGroups, '2'),
            active: uri.queryParameters['type'] == '2',
          ),
        ],
      ),
      ..._ensureHotSortFilter(uri, normalizedGroups),
    ];
  }

  bool _isHotComicsUri(Uri uri) {
    final String host = uri.host.trim().toLowerCase();
    final String path = uri.path.trim().toLowerCase();
    return path.startsWith('/comics') && host.contains('manga2026');
  }

  String _hotComicTypeHref(Uri uri, List<FilterGroupData> groups, String type) {
    final Map<String, String> query = _hotComicBaseQuery(uri, groups);
    query['type'] = type;
    return _replaceSortedQuery(uri, query).toString();
  }

  Map<String, String> _hotComicBaseQuery(
    Uri uri,
    List<FilterGroupData> groups,
  ) {
    final Map<String, String> query = Map<String, String>.from(
      uri.queryParameters,
    );
    for (final FilterGroupData group in groups) {
      for (final LinkAction option in group.options) {
        if (!option.active || option.href.trim().isEmpty) {
          continue;
        }
        final Uri? optionUri = Uri.tryParse(option.href);
        if (optionUri == null ||
            !optionUri.path.toLowerCase().startsWith('/comics')) {
          continue;
        }
        query.addAll(optionUri.queryParameters);
      }
    }
    query.remove('offset');
    query.remove('page');
    query.remove('limit');
    query.putIfAbsent('ordering', () => '-datetime_updated');
    return query;
  }

  List<FilterGroupData> _ensureHotSortFilter(
    Uri uri,
    List<FilterGroupData> groups,
  ) {
    final bool hasSortGroup = groups.any(
      (FilterGroupData group) => group.label.trim() == '排序',
    );
    if (hasSortGroup) {
      return groups;
    }
    final Map<String, String> baseQuery = _hotComicBaseQuery(uri, groups);
    final String activeOrdering = baseQuery['ordering'] ?? '-datetime_updated';
    LinkAction buildOption(String label, String ordering) {
      final Map<String, String> query = <String, String>{
        ...baseQuery,
        'ordering': ordering,
      };
      return LinkAction(
        label: label,
        href: _replaceSortedQuery(uri, query).toString(),
        active: activeOrdering == ordering,
      );
    }

    return <FilterGroupData>[
      ...groups,
      FilterGroupData(
        label: '排序',
        options: <LinkAction>[
          buildOption('最新更新', '-datetime_updated'),
          buildOption('最新上架', '-datetime_created'),
          buildOption('人气最高', '-popular'),
        ],
      ),
    ];
  }

  Uri _replaceSortedQuery(Uri uri, Map<String, String> queryParameters) {
    final List<MapEntry<String, String>> sortedQuery =
        queryParameters.entries.toList(growable: false)..sort((
          MapEntry<String, String> left,
          MapEntry<String, String> right,
        ) {
          return left.key.compareTo(right.key);
        });
    return uri.replace(
      path: '/comics',
      queryParameters: sortedQuery.isEmpty
          ? null
          : Map<String, String>.fromEntries(sortedQuery),
    );
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
    final Map<int, String> labels = <int, String>{1: '话', 2: '卷', 3: '番外篇'};
    for (final Object? item in asObjectList(rawTypes)) {
      final Map<String, Object?> map = asStringKeyMap(item);
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
          .map(asStringKeyMap)
          .toList(growable: false);
    }
    if (rawGroups is List) {
      return rawGroups
          .whereType<Map>()
          .map(asStringKeyMap)
          .toList(growable: false);
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

  Uint8List _aesCbcDecrypt({
    required String keyMaterial,
    required String encrypted,
  }) {
    final Uint8List key = Uint8List.fromList(utf8.encode(keyMaterial));
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
    return cipher.process(cipherBytes);
  }

  Uint8List _decodeCipherText(String payload) {
    final String normalized = _cleanText(payload);
    if (SiteHtmlPageParser._hexPattern.hasMatch(normalized) &&
        normalized.length.isEven) {
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
    return (value ?? '')
        .replaceAll(SiteHtmlPageParser._spacePattern, ' ')
        .trim();
  }

  String _scriptStringValue(String html, String variableName) {
    return _cleanText(extractAssignedJavaScriptString(html, variableName));
  }

  String _pageTitle(dom.Document document) {
    final String title = _cleanText(document.querySelector('title')?.text);
    if (title.isEmpty) {
      return 'EasyCopy';
    }
    return title.replaceFirst(RegExp(r'\s*-\s*(拷|熱辣|热辣)[^-]+$'), '');
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
