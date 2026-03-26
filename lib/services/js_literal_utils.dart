class JavaScriptLiteralParser {
  JavaScriptLiteralParser(this.source, {int start = 0}) : _index = start;

  final String source;
  int _index;

  Object? parse({bool requireExhausted = true}) {
    skipWhitespace();
    final Object? value = _parseValue();
    skipWhitespace();
    if (requireExhausted && !_isAtEnd) {
      _fail('发现多余内容');
    }
    return value;
  }

  void skipWhitespace() {
    while (!_isAtEnd) {
      final int char = source.codeUnitAt(_index);
      if (char == 0x20 ||
          char == 0x0A ||
          char == 0x0D ||
          char == 0x09 ||
          char == 0x0C) {
        _index += 1;
        continue;
      }
      break;
    }
  }

  bool consumeChar(int expected) {
    if (_isAtEnd || source.codeUnitAt(_index) != expected) {
      return false;
    }
    _index += 1;
    return true;
  }

  Object? _parseValue() {
    skipWhitespace();
    if (_isAtEnd) {
      _fail('意外结束');
    }

    final int char = source.codeUnitAt(_index);
    if (char == 0x5B) {
      return _parseArray();
    }
    if (char == 0x7B) {
      return _parseObject();
    }
    if (char == 0x22 || char == 0x27 || char == 0x60) {
      return _parseString();
    }
    if (char == 0x74) {
      return _parseKeyword('true', true);
    }
    if (char == 0x66) {
      return _parseKeyword('false', false);
    }
    if (char == 0x6E) {
      return _parseKeyword('null', null);
    }
    if (char == 0x2D || _isDigit(char)) {
      return _parseNumber();
    }

    _fail('无法识别的值');
  }

  List<Object?> _parseArray() {
    _expectChar(0x5B);
    final List<Object?> result = <Object?>[];
    skipWhitespace();
    if (consumeChar(0x5D)) {
      return result;
    }

    while (true) {
      result.add(_parseValue());
      skipWhitespace();
      if (consumeChar(0x5D)) {
        return result;
      }
      _expectChar(0x2C);
      skipWhitespace();
      if (consumeChar(0x5D)) {
        return result;
      }
    }
  }

  Map<String, Object?> _parseObject() {
    _expectChar(0x7B);
    final Map<String, Object?> result = <String, Object?>{};
    skipWhitespace();
    if (consumeChar(0x7D)) {
      return result;
    }

    while (true) {
      final String key = _parseObjectKey();
      skipWhitespace();
      _expectChar(0x3A);
      final Object? value = _parseValue();
      result[key] = value;
      skipWhitespace();
      if (consumeChar(0x7D)) {
        return result;
      }
      _expectChar(0x2C);
      skipWhitespace();
      if (consumeChar(0x7D)) {
        return result;
      }
    }
  }

  String _parseObjectKey() {
    skipWhitespace();
    if (_isAtEnd) {
      _fail('缺少对象键');
    }

    final int char = source.codeUnitAt(_index);
    if (char == 0x22 || char == 0x27 || char == 0x60) {
      return _parseString();
    }
    if (!_isIdentifierStart(char)) {
      _fail('对象键格式无效');
    }

    final int start = _index;
    _index += 1;
    while (!_isAtEnd && _isIdentifierPart(source.codeUnitAt(_index))) {
      _index += 1;
    }
    return source.substring(start, _index);
  }

  String _parseString() {
    final int quote = source.codeUnitAt(_index);
    _index += 1;
    final StringBuffer buffer = StringBuffer();

    while (!_isAtEnd) {
      final int char = source.codeUnitAt(_index);
      _index += 1;
      if (char == quote) {
        return buffer.toString();
      }
      if (char != 0x5C) {
        buffer.writeCharCode(char);
        continue;
      }

      if (_isAtEnd) {
        _fail('转义序列不完整');
      }
      final int escape = source.codeUnitAt(_index);
      _index += 1;
      switch (escape) {
        case 0x22:
          buffer.write('"');
        case 0x27:
          buffer.write("'");
        case 0x60:
          buffer.write('`');
        case 0x5C:
          buffer.write(r'\');
        case 0x2F:
          buffer.write('/');
        case 0x62:
          buffer.write('\b');
        case 0x66:
          buffer.write('\f');
        case 0x6E:
          buffer.write('\n');
        case 0x72:
          buffer.write('\r');
        case 0x74:
          buffer.write('\t');
        case 0x75:
          buffer.writeCharCode(_parseUnicodeEscape());
        default:
          buffer.writeCharCode(escape);
      }
    }

    _fail('字符串未闭合');
  }

  int _parseUnicodeEscape() {
    if (_index + 4 > source.length) {
      _fail('Unicode 转义不完整');
    }
    final String hex = source.substring(_index, _index + 4);
    final int? value = int.tryParse(hex, radix: 16);
    if (value == null) {
      _fail('Unicode 转义无效');
    }
    _index += 4;
    return value;
  }

  num _parseNumber() {
    final int start = _index;
    if (consumeChar(0x2D)) {
      if (_isAtEnd || !_isDigit(source.codeUnitAt(_index))) {
        _fail('数字格式无效');
      }
    }

    while (!_isAtEnd && _isDigit(source.codeUnitAt(_index))) {
      _index += 1;
    }
    if (consumeChar(0x2E)) {
      if (_isAtEnd || !_isDigit(source.codeUnitAt(_index))) {
        _fail('数字格式无效');
      }
      while (!_isAtEnd && _isDigit(source.codeUnitAt(_index))) {
        _index += 1;
      }
    }
    if (!_isAtEnd) {
      final int char = source.codeUnitAt(_index);
      if (char == 0x65 || char == 0x45) {
        _index += 1;
        if (!_isAtEnd) {
          final int sign = source.codeUnitAt(_index);
          if (sign == 0x2B || sign == 0x2D) {
            _index += 1;
          }
        }
        if (_isAtEnd || !_isDigit(source.codeUnitAt(_index))) {
          _fail('数字指数格式无效');
        }
        while (!_isAtEnd && _isDigit(source.codeUnitAt(_index))) {
          _index += 1;
        }
      }
    }

    final String raw = source.substring(start, _index);
    final num? value = num.tryParse(raw);
    if (value == null) {
      _fail('数字格式无效');
    }
    return value;
  }

  Object? _parseKeyword(String keyword, Object? value) {
    if (!source.startsWith(keyword, _index)) {
      _fail('关键字格式无效');
    }
    _index += keyword.length;
    return value;
  }

  void _expectChar(int expected) {
    if (!consumeChar(expected)) {
      _fail('缺少 `${String.fromCharCode(expected)}`');
    }
  }

  bool get _isAtEnd => _index >= source.length;

  Never _fail(String message) {
    throw FormatException('$message，位置：$_index');
  }

  bool _isDigit(int char) => char >= 0x30 && char <= 0x39;

  bool _isIdentifierStart(int char) {
    return (char >= 0x41 && char <= 0x5A) ||
        (char >= 0x61 && char <= 0x7A) ||
        char == 0x5F ||
        char == 0x24;
  }

  bool _isIdentifierPart(int char) {
    return _isIdentifierStart(char) || _isDigit(char);
  }
}

Object? parseJavaScriptLiteral(String source) {
  return JavaScriptLiteralParser(source).parse();
}

String extractAssignedJavaScriptString(String source, String variableName) {
  final String escapedName = RegExp.escape(variableName);
  final List<RegExp> patterns = <RegExp>[
    RegExp(
      '(?:^|[;\\s])(?:var|let|const)\\s+$escapedName\\s*=\\s*',
      caseSensitive: false,
      multiLine: true,
    ),
    RegExp(
      '(?:^|[;\\s])window\\.$escapedName\\s*=\\s*',
      caseSensitive: false,
      multiLine: true,
    ),
  ];

  for (final RegExp pattern in patterns) {
    for (final RegExpMatch match in pattern.allMatches(source)) {
      try {
        final Object? value = JavaScriptLiteralParser(
          source,
          start: match.end,
        ).parse(requireExhausted: false);
        if (value is String) {
          final String normalized = value.trim();
          if (normalized.isNotEmpty) {
            return normalized;
          }
        }
      } on FormatException {
        continue;
      }
    }
  }
  return '';
}

String extractJavaScriptCallStringArgument(
  String source,
  String functionName, {
  int argumentIndex = 0,
}) {
  final RegExp pattern = RegExp(
    '(?:^|[^\\w\$.])${RegExp.escape(functionName)}\\s*\\(\\s*',
    caseSensitive: false,
    multiLine: true,
  );

  for (final RegExpMatch match in pattern.allMatches(source)) {
    try {
      final JavaScriptLiteralParser parser = JavaScriptLiteralParser(
        source,
        start: match.end,
      );
      for (int index = 0; index <= argumentIndex; index += 1) {
        final Object? value = parser.parse(requireExhausted: false);
        if (index == argumentIndex) {
          return value is String ? value.trim() : '';
        }
        parser.skipWhitespace();
        if (!parser.consumeChar(0x2C)) {
          break;
        }
        parser.skipWhitespace();
      }
    } on FormatException {
      continue;
    }
  }
  return '';
}
