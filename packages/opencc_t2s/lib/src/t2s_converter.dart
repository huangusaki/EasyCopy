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

  static final Map<String, String> _normalization = _decodePairs(
    kNormalization,
  );
  static final Map<String, String> _phrases = _decodePhrases(kPhrases);
  static final Map<String, String> _charactersExt = _decodePairs(
    kCharactersExt,
  );
  static final Map<String, String> _characters = _decodePairs(kCharacters);

  static final int _maxPhraseUnits = _phrases.keys.fold<int>(
    0,
    (int longest, String key) => key.length > longest ? key.length : longest,
  );
  static final int _minPhraseUnits = _phrases.keys.fold<int>(
    _maxPhraseUnits,
    (int shortest, String key) => key.length < shortest ? key.length : shortest,
  );

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
    final int length = text.length;
    final StringBuffer buffer = StringBuffer();
    bool changed = false;
    int index = 0;

    while (index < length) {
      final int units = _codePointUnits(text, index);
      final String source = text.substring(index, index + units);
      final String? replacement = _normalization[source];
      if (replacement == null) {
        buffer.write(source);
      } else {
        buffer.write(replacement);
        changed = true;
      }
      index += units;
    }

    return changed ? buffer.toString() : text;
  }

  static String _convertGroup(String text) {
    final int length = text.length;
    final StringBuffer buffer = StringBuffer();
    bool changed = false;
    int index = 0;

    while (index < length) {
      String? replacement;
      int consumed = 0;

      int upper = _maxPhraseUnits;
      if (index + upper > length) {
        upper = length - index;
      }
      for (int units = upper; units >= _minPhraseUnits; units--) {
        final String? phrase = _phrases[text.substring(index, index + units)];
        if (phrase != null) {
          replacement = phrase;
          consumed = units;
          break;
        }
      }

      if (replacement == null) {
        consumed = _codePointUnits(text, index);
        final String source = text.substring(index, index + consumed);
        replacement = _charactersExt[source] ?? _characters[source];
        if (replacement == null) {
          buffer.write(source);
          index += consumed;
          continue;
        }
      }

      buffer.write(replacement);
      changed = true;
      index += consumed;
    }

    return changed ? buffer.toString() : text;
  }

  /// Length in UTF-16 code units of the code point starting at [index].
  static int _codePointUnits(String text, int index) {
    final int unit = text.codeUnitAt(index);
    if (unit >= 0xD800 && unit <= 0xDBFF && index + 1 < text.length) {
      final int next = text.codeUnitAt(index + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) {
        return 2;
      }
    }
    return 1;
  }

  static Map<String, String> _decodePairs(String data) {
    final Map<String, String> entries = <String, String>{};
    final List<int> runes = data.runes.toList(growable: false);
    for (int i = 0; i < runes.length; i += 2) {
      entries[String.fromCharCode(runes[i])] = String.fromCharCode(
        runes[i + 1],
      );
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
