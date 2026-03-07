import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

typedef ReaderProgressDirectoryProvider = Future<Directory> Function();
typedef ReaderProgressNowProvider = DateTime Function();

enum ReaderProgressMode { scroll, paged }

@immutable
class ReaderPosition {
  const ReaderPosition({
    required this.mode,
    this.offset = 0,
    this.pageIndex = 0,
    this.pageOffset = 0,
  });

  factory ReaderPosition.scroll({double offset = 0}) {
    return ReaderPosition(
      mode: ReaderProgressMode.scroll,
      offset: offset,
    );
  }

  factory ReaderPosition.paged({
    int pageIndex = 0,
    double pageOffset = 0,
  }) {
    return ReaderPosition(
      mode: ReaderProgressMode.paged,
      pageIndex: pageIndex,
      pageOffset: pageOffset,
    );
  }

  factory ReaderPosition.fromJson(Map<String, Object?> json) {
    final String rawMode = (json['mode'] as String?)?.trim() ?? '';
    if (rawMode == 'paged' || json.containsKey('pageIndex')) {
      return ReaderPosition.paged(
        pageIndex: ((json['pageIndex'] as num?) ?? 0).round().clamp(0, 999999),
        pageOffset: ((json['pageOffset'] as num?) ?? 0).toDouble(),
      );
    }
    return ReaderPosition.scroll(
      offset: ((json['offset'] as num?) ?? 0).toDouble(),
    );
  }

  final ReaderProgressMode mode;
  final double offset;
  final int pageIndex;
  final double pageOffset;

  bool get isScroll => mode == ReaderProgressMode.scroll;

  bool get isPaged => mode == ReaderProgressMode.paged;

  ReaderPosition copyWith({
    ReaderProgressMode? mode,
    double? offset,
    int? pageIndex,
    double? pageOffset,
  }) {
    return ReaderPosition(
      mode: mode ?? this.mode,
      offset: offset ?? this.offset,
      pageIndex: pageIndex ?? this.pageIndex,
      pageOffset: pageOffset ?? this.pageOffset,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'mode': switch (mode) {
        ReaderProgressMode.scroll => 'scroll',
        ReaderProgressMode.paged => 'paged',
      },
      'offset': offset,
      'pageIndex': pageIndex,
      'pageOffset': pageOffset,
    };
  }
}

@immutable
class ReaderProgressEntry {
  const ReaderProgressEntry({
    required this.key,
    required this.position,
    required this.updatedAt,
  });

  factory ReaderProgressEntry.fromJson(Map<String, Object?> json) {
    return ReaderProgressEntry(
      key: (json['key'] as String?) ?? '',
      position: ReaderPosition.fromJson(json),
      updatedAt:
          DateTime.tryParse((json['updatedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final String key;
  final ReaderPosition position;
  final DateTime updatedAt;

  ReaderProgressEntry copyWith({
    ReaderPosition? position,
    DateTime? updatedAt,
  }) {
    return ReaderProgressEntry(
      key: key,
      position: position ?? this.position,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'key': key,
      ...position.toJson(),
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

  Future<ReaderPosition?> readPosition(String key) async {
    await ensureInitialized();
    final ReaderProgressEntry? match = _entryForKey(key);
    if (match == null) {
      return null;
    }
    return match.position;
  }

  Future<double?> readOffset(String key) async {
    final ReaderPosition? position = await readPosition(key);
    if (position == null || !position.isScroll) {
      return null;
    }
    return position.offset;
  }

  Future<void> writePosition(String key, ReaderPosition position) async {
    await ensureInitialized();
    final String normalizedKey = key.trim();
    if (normalizedKey.isEmpty) {
      return;
    }

    final ReaderPosition normalizedPosition = _normalizePosition(position);
    final DateTime now = _now();
    final int index = _entries.indexWhere(
      (ReaderProgressEntry entry) => entry.key == normalizedKey,
    );
    if (index >= 0) {
      _entries[index] = _entries[index].copyWith(
        position: normalizedPosition,
        updatedAt: now,
      );
    } else {
      _entries.add(
        ReaderProgressEntry(
          key: normalizedKey,
          position: normalizedPosition,
          updatedAt: now,
        ),
      );
    }
    _trim();
    await _persist();
  }

  Future<void> writeOffset(String key, double offset) {
    return writePosition(key, ReaderPosition.scroll(offset: offset));
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

  ReaderPosition _normalizePosition(ReaderPosition position) {
    if (position.isPaged) {
      return ReaderPosition.paged(
        pageIndex: position.pageIndex < 0 ? 0 : position.pageIndex,
        pageOffset: position.pageOffset.isFinite && position.pageOffset >= 0
            ? position.pageOffset
            : 0,
      );
    }
    return ReaderPosition.scroll(
      offset: position.offset.isFinite && position.offset >= 0
          ? position.offset
          : 0,
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
