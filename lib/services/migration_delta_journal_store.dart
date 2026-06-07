import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

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
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static final MigrationDeltaJournalStore instance =
      MigrationDeltaJournalStore();

  final JournalDirProvider _directoryProvider;

  Future<void>? _initialization;
  File? _file;

  Future<void> ensureInitialized() {
    return _initialization ??= _initialize();
  }

  Future<List<MigrationDeltaEntry>> read(String storageKey) async {
    await ensureInitialized();
    final File file = _file!;
    if (!await file.exists()) {
      return const <MigrationDeltaEntry>[];
    }
    try {
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return const <MigrationDeltaEntry>[];
      }
      final String persistedStorageKey =
          (decoded['storageKey'] as String?)?.trim() ?? '';
      if (persistedStorageKey != storageKey) {
        return const <MigrationDeltaEntry>[];
      }
      final List<Object?> rawEntries =
          (decoded['entries'] as List<Object?>?) ?? const <Object?>[];
      return rawEntries
          .whereType<Map<Object?, Object?>>()
          .map(
            (Map<Object?, Object?> entry) => MigrationDeltaEntry.fromJson(
              entry.map(
                (Object? key, Object? value) => MapEntry(key.toString(), value),
              ),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const <MigrationDeltaEntry>[];
    }
  }

  Future<void> append(String storageKey, MigrationDeltaEntry entry) async {
    final List<MigrationDeltaEntry> entries = await read(storageKey);
    await _write(storageKey, <MigrationDeltaEntry>[...entries, entry]);
  }

  Future<void> clear([String? storageKey]) async {
    await ensureInitialized();
    final File file = _file!;
    if (!await file.exists()) {
      return;
    }
    if (storageKey == null) {
      await file.delete();
      return;
    }
    final List<MigrationDeltaEntry> entries = await read(storageKey);
    if (entries.isEmpty) {
      await file.delete();
    } else {
      await _write(storageKey, const <MigrationDeltaEntry>[]);
    }
  }

  Future<void> _write(
    String storageKey,
    List<MigrationDeltaEntry> entries,
  ) async {
    await ensureInitialized();
    final File file = _file!;
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'storageKey': storageKey,
        'entries': entries
            .map((MigrationDeltaEntry entry) => entry.toJson())
            .toList(),
      }),
      flush: true,
    );
  }

  Future<void> _initialize() async {
    final Directory directory = await _directoryProvider();
    final Directory stateDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}download_queue',
    );
    await stateDirectory.create(recursive: true);
    _file = File(
      '${stateDirectory.path}${Platform.pathSeparator}storage_migration_delta.json',
    );
  }
}
