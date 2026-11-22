import 'dictionary_data.dart';

/// Converts traditional Chinese to simplified Chinese.
///
/// This reproduces OpenCC's `t2s.json` pipeline exactly:
///
/// 1. a normalization pass over `CJK_Compatibility_Ideographs`;
/// 2. one greedy longest-prefix pass over the `short_circuit` dictionary group
///    `[TSPhrases, TSCharactersExt, TSCharacters]` — the first dictionary that
///    matches at a position wins, using that dictionary's longest key.
///
/// `t2s.json` declares no `segmentation`, so no segmentation runs here either.
///
/// One deliberate difference from OpenCC: ideographic description sequences
/// (U+2FF0-U+2FFF) are not treated as atomic, so characters inside them are
/// converted like any other text.
class T2SConverter {
  /// Creates a converter that memoizes up to [cacheSize] recent conversions.
  ///
  /// Pass `0` to disable memoization.
  T2SConverter({int cacheSize = 4096}) : _cacheCapacity = cacheSize;

  static final Map<int, String> _normalization = _decodePairs(kNormalization);
  static final Map<String, String> _phrases = _decodePhrases(kPhrases);
  static final Map<int, String> _charactersExt = _decodePairs(kCharactersExt);
  static final Map<int, String> _characters = _decodePairs(kCharacters);

  static final Map<int, List<int>> _phraseLengths = _indexPhraseLengths();

  static Map<int, List<int>> _indexPhraseLengths() {
    final lengths = <int, Set<int>>{};
    for (final phrase in _phrases.keys) {
      (lengths[phrase.codeUnitAt(0)] ??= <int>{}).add(phrase.length);
    }
    return lengths.map(
      (first, sizes) =>
          MapEntry(first, sizes.toList()..sort((a, b) => b.compareTo(a))),
    );
  }

  final int _cacheCapacity;

  /// Insertion-ordered, so the first key is the least recently used one.
  final Map<String, String> _cache = <String, String>{};

  /// Converts [text], returning it unchanged when nothing matches.
  String convert(String text) {
    if (text.isEmpty) {
      return text;
    }
    if (_cacheCapacity <= 0) {
      return _convert(text);
    }

    final String? cached = _cache.remove(text);
    if (cached != null) {
      _cache[text] = cached;
      return cached;
    }

    final String converted = _convert(text);
    if (_cache.length >= _cacheCapacity) {
      _cache.remove(_cache.keys.first);
    }
    _cache[text] = converted;
    return converted;
  }

  /// Drops every memoized conversion.
  void clearCache() => _cache.clear();

  static String _convert(String text) => _convertGroup(_normalize(text));

  static String _normalize(String text) {
    StringBuffer? output;
    int unchangedStart = 0;
    int index = 0;
    while (index < text.length) {
      final rune = _codePointAt(text, index);
      final next = index + (rune > 0xffff ? 2 : 1);
      final replacement = _normalization[rune];
      if (replacement != null) {
        (output ??= StringBuffer())
          ..write(text.substring(unchangedStart, index))
          ..write(replacement);
        unchangedStart = next;
      }
      index = next;
    }
    if (output == null) return text;
    return (output..write(text.substring(unchangedStart))).toString();
  }

  static String _convertGroup(String text) {
    StringBuffer? output;
    int unchangedStart = 0;
    int index = 0;
    while (index < text.length) {
      String? replacement;
      int consumed = 0;
      final lengths = _phraseLengths[text.codeUnitAt(index)];
      if (lengths != null) {
        for (final units in lengths) {
          if (index + units > text.length) continue;
          replacement = _phrases[text.substring(index, index + units)];
          if (replacement != null) {
            consumed = units;
            break;
          }
        }
      }
      if (replacement == null) {
        final rune = _codePointAt(text, index);
        consumed = rune > 0xffff ? 2 : 1;
        replacement = _charactersExt[rune] ?? _characters[rune];
      }
      if (replacement != null &&
          (replacement.length != consumed ||
              !text.startsWith(replacement, index))) {
        (output ??= StringBuffer())
          ..write(text.substring(unchangedStart, index))
          ..write(replacement);
        unchangedStart = index + consumed;
      }
      // Identity phrases still consume the entire match before character lookup.
      index += consumed;
    }
    if (output == null) return text;
    return (output..write(text.substring(unchangedStart))).toString();
  }

  static int _codePointAt(String text, int index) {
    final first = text.codeUnitAt(index);
    if (first >= 0xd800 && first <= 0xdbff && index + 1 < text.length) {
      final second = text.codeUnitAt(index + 1);
      if (second >= 0xdc00 && second <= 0xdfff) {
        return 0x10000 + ((first - 0xd800) << 10) + second - 0xdc00;
      }
    }
    return first;
  }

  static Map<int, String> _decodePairs(String data) {
    final entries = <int, String>{};
    final runes = data.runes.iterator;
    while (runes.moveNext()) {
      final source = runes.current;
      runes.moveNext();
      entries[source] = String.fromCharCode(runes.current);
    }
    return entries;
  }

  static Map<String, String> _decodePhrases(String data) {
    final Map<String, String> entries = <String, String>{};
    for (final String line in data.split('\n')) {
      if (line.isEmpty) {
        continue;
      }
      final int tab = line.indexOf('\t');
      entries[line.substring(0, tab)] = line.substring(tab + 1);
    }
    return entries;
  }
}
