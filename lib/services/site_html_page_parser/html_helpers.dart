part of '../site_html_page_parser.dart';

extension _SiteHtmlHelpers on SiteHtmlPageParser {
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
