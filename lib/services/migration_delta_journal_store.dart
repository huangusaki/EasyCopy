import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:reader/services/persistence/atomic_json_file.dart';

typedef JournalDirProvider = Future<Directory> Function();

enum MigrationDeltaKind { upsertChapter, deleteChapter, deleteComic }

class MigrationDeltaEntry {
  const MigrationDeltaEntry({
    required this.kind,
    required this.relativePath,
    required this.updatedAt,
  });

  factory MigrationDeltaEntry.fromJson(Map<String, Object?> json) {
    return MigrationDeltaEntry(
      kind: MigrationDeltaKind.values.firstWhere(
        (MigrationDeltaKind entry) => entry.name == json['kind'],
        orElse: () => MigrationDeltaKind.upsertChapter,
      ),
      relativePath: (json['relativePath'] as String?)?.trim() ?? '',
      updatedAt:
          DateTime.tryParse((json['updatedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final MigrationDeltaKind kind;
  final String relativePath;
  final DateTime updatedAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.name,
      'relativePath': relativePath,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}

class MigrationDeltaJournalStore {
  MigrationDeltaJournalStore({JournalDirProvider? directoryProvider})
    : _file = AtomicJsonFile<_MigrationJournal>(
        directoryProvider: directoryProvider ?? getApplicationSupportDirectory,
        relativePath: 'download_queue/storage_migration_delta.json',
        decode: _MigrationJournal.fromJson,
        encode: (_MigrationJournal value) => value.toJson(),
      );

  static final MigrationDeltaJournalStore instance =
      MigrationDeltaJournalStore();

  final AtomicJsonFile<_MigrationJournal> _file;

  Future<void> ensureInitialized() => _file.ensureInitialized();

  Future<List<MigrationDeltaEntry>> read(String storageKey) async {
    final _MigrationJournal? journal = await _file.read();
    return journal?.storageKey == storageKey
        ? journal!.entries
        : const <MigrationDeltaEntry>[];
  }

  Future<void> append(String storageKey, MigrationDeltaEntry entry) {
    return _file.update(
      (_MigrationJournal? current) =>
          _MigrationJournal(storageKey, <MigrationDeltaEntry>[
            if (current?.storageKey == storageKey) ...current!.entries,
            entry,
          ]),
    );
  }

  Future<void> clear([String? storageKey]) {
    return _file.clear(
      when: storageKey == null
          ? null
          : (_MigrationJournal? current) => current?.storageKey == storageKey,
    );
  }
}

class _MigrationJournal {
  const _MigrationJournal(this.storageKey, this.entries);

  factory _MigrationJournal.fromJson(Object? value) {
    final Map<String, Object?> json = Map<String, Object?>.from(value as Map);
    final List<Object?> entries =
        (json['entries'] as List<Object?>?) ?? const <Object?>[];
    return _MigrationJournal(
      (json['storageKey'] as String?)?.trim() ?? '',
      entries
          .whereType<Map>()
          .map(
            (Map entry) =>
                MigrationDeltaEntry.fromJson(Map<String, Object?>.from(entry)),
          )
          .toList(growable: false),
    );
  }

  final String storageKey;
  final List<MigrationDeltaEntry> entries;

  Map<String, Object?> toJson() => <String, Object?>{
    'storageKey': storageKey,
    'entries': entries
        .map((MigrationDeltaEntry entry) => entry.toJson())
        .toList(),
  };
}
