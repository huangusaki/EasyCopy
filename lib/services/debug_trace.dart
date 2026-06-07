import 'dart:convert';

import 'package:flutter/foundation.dart';

class DebugTrace {
  const DebugTrace._();

  static void log(
    String event, [
    Map<String, Object?> fields = const <String, Object?>{},
  ]) {
    if (!kDebugMode) {
      return;
    }
    final Map<String, Object?> payload = <String, Object?>{'event': event};
    for (final MapEntry<String, Object?> entry in fields.entries) {
      if (entry.value == null) {
        continue;
      }
      payload[entry.key] = entry.value;
    }
    debugPrint('[trace] ${jsonEncode(payload)}');
  }
}
