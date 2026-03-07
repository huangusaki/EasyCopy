import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

typedef ReaderProgressDirectoryProvider = Future<Directory> Function();
typedef ReaderProgressNowProvider = DateTime Function();

@immutable
class ReaderProgressEntry {
  const ReaderProgressEntry({
    required this.key,
    required this.offset,
    required this.updatedAt,
  });

  factory ReaderProgressEntry.fromJson(Map<String, Object?> json) {
    return ReaderProgressEntry(
      key: (json['key'] as String?) ?? '',
      offset: (json['offset'] as num?)?.toDouble() ?? 0,
      updatedAt:
          DateTime.tryParse((json['updatedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final String key;
  final double offset;
  final DateTime updatedAt;

  ReaderProgressEntry copyWith({double? offset, DateTime? updatedAt}) {
    return ReaderProgressEntry(
      key: key,
      offset: offset ?? this.offset,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'key': key,
      'offset': offset,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

class ReaderProgressStore {
  ReaderProgressStore({
    ReaderProgressDirectoryProvider? directoryProvider,
    ReaderProgressNowProvider? now,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _now = now ?? DateTime.now;

  static final ReaderProgressStore instance = ReaderProgressStore();

  static const int maxEntries = 60;

  final ReaderProgressDirectoryProvider _directoryProvider;
  final ReaderProgressNowProvider _now;

  Future<void>? _initialization;
  List<ReaderProgressEntry> _entries = <ReaderProgressEntry>[];

  Future<void> ensureInitialized() {
    return _initialization ??= _initialize();
  }

  Future<double?> readOffset(String key) async {
    await ensureInitialized();
    final ReaderProgressEntry? match = _entryForKey(key);
    if (match == null) {
      return null;
    }
    return match.offset;
  }

  Future<void> writeOffset(String key, double offset) async {
    await ensureInitialized();
    final String normalizedKey = key.trim();
    if (normalizedKey.isEmpty) {
      return;
    }

    final double normalizedOffset = offset.isFinite && offset >= 0 ? offset : 0;
    final DateTime now = _now();
    final int index = _entries.indexWhere(
      (ReaderProgressEntry entry) => entry.key == normalizedKey,
    );
    if (index >= 0) {
      _entries[index] = _entries[index].copyWith(
        offset: normalizedOffset,
        updatedAt: now,
      );
    } else {
      _entries.add(
        ReaderProgressEntry(
          key: normalizedKey,
          offset: normalizedOffset,
          updatedAt: now,
        ),
      );
    }
    _trim();
    await _persist();
  }

  Future<void> remove(String key) async {
    await ensureInitialized();
    _entries.removeWhere((ReaderProgressEntry entry) => entry.key == key);
    await _persist();
  }

  ReaderProgressEntry? _entryForKey(String key) {
    final String normalizedKey = key.trim();
    if (normalizedKey.isEmpty) {
      return null;
    }
    return _entries.cast<ReaderProgressEntry?>().firstWhere(
      (ReaderProgressEntry? entry) => entry?.key == normalizedKey,
      orElse: () => null,
    );
  }

  Future<void> _initialize() async {
    try {
      final File file = await _progressFile();
      if (!await file.exists()) {
        return;
      }
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) {
        return;
      }
      _entries = decoded
          .whereType<Map>()
          .map(
            (Map<Object?, Object?> value) => ReaderProgressEntry.fromJson(
              value.map(
                (Object? key, Object? nestedValue) =>
                    MapEntry(key.toString(), nestedValue),
              ),
            ),
          )
          .toList(growable: true);
      _trim();
    } catch (_) {
      _entries = <ReaderProgressEntry>[];
    }
  }

  Future<File> _progressFile() async {
    final Directory directory = await _directoryProvider();
    return File(
      '${directory.path}${Platform.pathSeparator}reader_progress.json',
    );
  }

  void _trim() {
    _entries.sort(
      (ReaderProgressEntry left, ReaderProgressEntry right) =>
          right.updatedAt.compareTo(left.updatedAt),
    );
    if (_entries.length > maxEntries) {
      _entries = _entries.take(maxEntries).toList(growable: true);
    }
  }

  Future<void> _persist() async {
    try {
      final File file = await _progressFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(
          _entries.map((ReaderProgressEntry entry) => entry.toJson()).toList(),
        ),
      );
    } catch (_) {
      // Best-effort persistence only.
    }
  }
}
