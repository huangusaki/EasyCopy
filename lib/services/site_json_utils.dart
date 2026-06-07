Map<String, Object?> asStringKeyMap(Object? value) {
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

List<Object?> asObjectList(Object? value) {
  if (value is List<Object?>) {
    return value;
  }
  if (value is List) {
    return value.cast<Object?>();
  }
  return const <Object?>[];
}

String pickString(Map<String, Object?> source, List<String> keys) {
  for (final String key in keys) {
    final Object? value = source[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return '';
}

String pickFirstString(List<Map<String, Object?>> sources, List<String> keys) {
  for (final Map<String, Object?> source in sources) {
    final String value = pickString(source, keys);
    if (value.isNotEmpty) {
      return value;
    }
  }
  return '';
}

int pickInt(
  Map<String, Object?> source,
  List<String> keys, {
  int fallback = 0,
}) {
  for (final String key in keys) {
    final Object? value = source[key];
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      final int? parsed = int.tryParse(value.trim());
      if (parsed != null) {
        return parsed;
      }
    }
  }
  return fallback;
}

bool pickBool(Map<String, Object?> source, String key) {
  final Object? value = source[key];
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    return value == '1' || value.toLowerCase() == 'true';
  }
  return false;
}
