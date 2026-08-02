// Regenerates `lib/src/dictionary_data.dart` from an OpenCC checkout.
//
// Usage:
//   dart run tool/generate_dictionary.dart --opencc <path/to/OpenCC>
//
// `<path/to/OpenCC>` may be either an OpenCC repository root or its
// `data/dictionary` directory. Only the four dictionaries referenced by
// `data/config/t2s.json` are read:
//
//   normalization    CJK_Compatibility_Ideographs.txt
//   conversion chain TSPhrases.txt, TSCharactersExt, TSCharacters.txt
//
// TSCharactersExt has no source file upstream; it is derived from the
// `# @tofu-risk:` annotations inside TSCharacters.txt, exactly as
// `data/scripts/extract_tofu_risk.py` does.

import 'dart:convert';
import 'dart:io';

const String _tofuPrefix = '# @tofu-risk:';

/// Code points per line in the emitted character tables.
const int _charsPerLine = 64;

void main(List<String> args) {
  final String? openccPath = _parseOpenccPath(args);
  if (openccPath == null) {
    stderr.writeln(
      'Usage: dart run tool/generate_dictionary.dart --opencc <path/to/OpenCC>',
    );
    exitCode = 64;
    return;
  }

  final Directory dictDir = _resolveDictionaryDir(openccPath);
  if (!dictDir.existsSync()) {
    stderr.writeln('Dictionary directory not found: ${dictDir.path}');
    exitCode = 66;
    return;
  }

  final Map<String, String> normalization = _readDict(
    dictDir,
    'CJK_Compatibility_Ideographs.txt',
  );
  final Map<String, String> phrases = _readDict(dictDir, 'TSPhrases.txt');
  final Map<String, String> characters = _readDict(dictDir, 'TSCharacters.txt');
  final Map<String, String> extension = _readTofuRiskDict(dictDir);

  // TSCharacters is the last dictionary of a short_circuit group and its keys
  // are all single code points, so an entry mapping a key to itself behaves
  // exactly like no entry at all: both emit the key and advance one code point.
  _requireSingleCodePointKeys(normalization, 'CJK_Compatibility_Ideographs');
  _requireSingleCodePointKeys(extension, 'TSCharactersExt');
  _requireSingleCodePointKeys(characters, 'TSCharacters');
  final int identityCount = characters.length;
  characters.removeWhere((String key, String value) => key == value);

  final File output = File.fromUri(
    Platform.script.resolve('../lib/src/dictionary_data.dart'),
  );
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(
    _render(
      normalization: normalization,
      phrases: phrases,
      extension: extension,
      characters: characters,
    ),
  );

  stdout.writeln('Wrote ${output.path}');
  stdout.writeln('  normalization   ${normalization.length}');
  stdout.writeln('  phrases         ${phrases.length}');
  stdout.writeln('  extension       ${extension.length}');
  stdout.writeln(
    '  characters      ${characters.length} '
    '(${identityCount - characters.length} identity entries dropped)',
  );
}

String? _parseOpenccPath(List<String> args) {
  for (int i = 0; i < args.length - 1; i++) {
    if (args[i] == '--opencc') {
      return args[i + 1];
    }
  }
  return null;
}

Directory _resolveDictionaryDir(String path) {
  final Directory candidate = Directory('$path/data/dictionary');
  return candidate.existsSync() ? candidate : Directory(path);
}

/// Reads an OpenCC text dictionary, keeping the first candidate of each entry
/// (which is what `DictEntry::GetDefault()` returns).
Map<String, String> _readDict(Directory dir, String name) {
  final Map<String, String> entries = <String, String>{};
  final List<String> lines = File(
    '${dir.path}/$name',
  ).readAsLinesSync(encoding: utf8);
  for (final String line in lines) {
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    final int tab = line.indexOf('\t');
    if (tab <= 0) {
      throw FormatException('Malformed entry in $name: $line');
    }
    entries[line.substring(0, tab)] = line.substring(tab + 1).split(' ').first;
  }
  return entries;
}

/// Rebuilds TSCharactersExt: every mapping that directly follows a
/// `# @tofu-risk:` annotation, with the leading identity candidate stripped.
Map<String, String> _readTofuRiskDict(Directory dir) {
  final Map<String, String> entries = <String, String>{};
  final List<String> lines = File(
    '${dir.path}/TSCharacters.txt',
  ).readAsLinesSync(encoding: utf8);
  for (int i = 0; i < lines.length; i++) {
    if (!lines[i].startsWith(_tofuPrefix)) {
      continue;
    }
    final String mapping = lines[i + 1];
    final int tab = mapping.indexOf('\t');
    final String key = mapping.substring(0, tab);
    final List<String> values = mapping.substring(tab + 1).split(' ');
    if (values.first == key) {
      values.removeAt(0);
    }
    entries[key] = values.first;
  }
  return entries;
}

void _requireSingleCodePointKeys(Map<String, String> entries, String name) {
  for (final MapEntry<String, String> entry in entries.entries) {
    if (entry.key.runes.length != 1 || entry.value.runes.length != 1) {
      throw StateError(
        '$name is no longer a single-code-point dictionary: '
        '${entry.key} -> ${entry.value}',
      );
    }
  }
}

String _render({
  required Map<String, String> normalization,
  required Map<String, String> phrases,
  required Map<String, String> extension,
  required Map<String, String> characters,
}) {
  final StringBuffer buffer = StringBuffer()
    ..writeln('// GENERATED FILE - DO NOT EDIT.')
    ..writeln('//')
    ..writeln('// Regenerate with:')
    ..writeln(
      '//   dart run tool/generate_dictionary.dart --opencc <path/to/OpenCC>',
    )
    ..writeln('//')
    ..writeln('// Dictionary data: Open Chinese Convert (OpenCC),')
    ..writeln('// https://github.com/BYVoid/OpenCC, Apache License 2.0.')
    ..writeln()
    ..writeln('/// `CJK_Compatibility_Ideographs`: the normalization pass.')
    ..writeln('///')
    ..writeln('/// Alternating key/value code points.')
    ..write(_renderCharTable('kNormalization', normalization))
    ..writeln()
    ..writeln('/// `TSPhrases`: first dictionary of the short-circuit group.')
    ..writeln('///')
    ..writeln('/// Tab-separated key/value, one entry per line.')
    ..write(_renderPhraseTable('kPhrases', phrases))
    ..writeln()
    ..writeln('/// `TSCharactersExt`: second dictionary of the group, derived')
    ..writeln('/// from the `@tofu-risk` annotations in `TSCharacters`.')
    ..writeln('///')
    ..writeln('/// Alternating key/value code points.')
    ..write(_renderCharTable('kCharactersExt', extension))
    ..writeln()
    ..writeln('/// `TSCharacters`: last dictionary of the group, with entries')
    ..writeln('/// mapping a key to itself removed.')
    ..writeln('///')
    ..writeln('/// Alternating key/value code points.')
    ..write(_renderCharTable('kCharacters', characters));
  return buffer.toString();
}

String _renderCharTable(String name, Map<String, String> entries) {
  final StringBuffer flat = StringBuffer();
  for (final String key in entries.keys.toList()..sort()) {
    flat
      ..write(key)
      ..write(entries[key]);
  }

  final List<int> runes = flat.toString().runes.toList();
  final StringBuffer buffer = StringBuffer('const String $name =');
  for (int i = 0; i < runes.length; i += _charsPerLine) {
    final int end = (i + _charsPerLine).clamp(0, runes.length);
    buffer
      ..writeln()
      ..write('    ')
      ..write(_quote(String.fromCharCodes(runes.sublist(i, end))));
  }
  buffer.writeln(';');
  return buffer.toString();
}

String _renderPhraseTable(String name, Map<String, String> entries) {
  final StringBuffer buffer = StringBuffer('const String $name =');
  for (final String key in entries.keys.toList()..sort()) {
    buffer
      ..writeln()
      ..write('    ')
      ..write(_quote('$key\t${entries[key]}\n'));
  }
  buffer.writeln(';');
  return buffer.toString();
}

String _quote(String value) {
  final String escaped = value
      .replaceAll(r'\', r'\\')
      .replaceAll(r'$', r'\$')
      .replaceAll("'", r"\'")
      .replaceAll('\t', r'\t')
      .replaceAll('\n', r'\n');
  return "'$escaped'";
}
