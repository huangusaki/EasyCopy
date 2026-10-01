import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:reader/models/app_preferences.dart';
import 'package:reader/services/persistence/atomic_json_file.dart';

typedef MigrationDirProvider = Future<Directory> Function();

enum DownloadStorageMigrationStep { copying, switching, cleaning }

class PendingDownloadStorageMigration {
  const PendingDownloadStorageMigration({
    required this.from,
    required this.to,
    required this.createdAt,
    required this.storageKey,
    this.phase = DownloadStorageMigrationStep.copying,
    this.copiedPaths,
    this.resumeQueueAfterMigration = false,
  });

  factory PendingDownloadStorageMigration.fromJson(Map<String, Object?> json) {
    return PendingDownloadStorageMigration(
      from: DownloadPreferences.fromJson(
        ((json['from'] as Map<Object?, Object?>?) ?? const <Object?, Object?>{})
            .map(
              (Object? key, Object? value) => MapEntry(key.toString(), value),
            ),
      ),
      to: DownloadPreferences.fromJson(
        ((json['to'] as Map<Object?, Object?>?) ?? const <Object?, Object?>{})
            .map(
              (Object? key, Object? value) => MapEntry(key.toString(), value),
            ),
      ),
      createdAt:
          DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      storageKey: (json['storageKey'] as String?)?.trim() ?? '',
      phase: DownloadStorageMigrationStep.values.firstWhere(
        (DownloadStorageMigrationStep entry) => entry.name == json['phase'],
        orElse: () => DownloadStorageMigrationStep.copying,
      ),
      copiedPaths: (json['copiedPaths'] as List?)?.cast<String>(),
      resumeQueueAfterMigration: json['resumeQueueAfterMigration'] == true,
    );
  }

  final DownloadPreferences from;
  final DownloadPreferences to;
  final DateTime createdAt;
  final String storageKey;
  final DownloadStorageMigrationStep phase;
  final List<String>? copiedPaths;
  final bool resumeQueueAfterMigration;

  PendingDownloadStorageMigration copyWith({
    DownloadPreferences? from,
    DownloadPreferences? to,
    DateTime? createdAt,
    String? storageKey,
    DownloadStorageMigrationStep? phase,
    List<String>? copiedPaths,
    bool? resumeQueueAfterMigration,
  }) {
    return PendingDownloadStorageMigration(
      from: from ?? this.from,
      to: to ?? this.to,
      createdAt: createdAt ?? this.createdAt,
      storageKey: storageKey ?? this.storageKey,
      phase: phase ?? this.phase,
      copiedPaths: copiedPaths ?? this.copiedPaths,
      resumeQueueAfterMigration:
          resumeQueueAfterMigration ?? this.resumeQueueAfterMigration,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'from': from.toJson(),
      'to': to.toJson(),
      'createdAt': createdAt.toIso8601String(),
      'storageKey': storageKey,
      'phase': phase.name,
      'copiedPaths': copiedPaths,
      'resumeQueueAfterMigration': resumeQueueAfterMigration,
    };
  }
}

class DownloadStorageMigrationStore {
  DownloadStorageMigrationStore({MigrationDirProvider? directoryProvider})
    : _file = AtomicJsonFile<PendingDownloadStorageMigration>(
        directoryProvider: directoryProvider ?? getApplicationSupportDirectory,
        relativePath: 'download_queue/storage_migration.json',
        decode: (Object? json) => PendingDownloadStorageMigration.fromJson(
          Map<String, Object?>.from(json as Map),
        ),
        encode: (PendingDownloadStorageMigration value) => value.toJson(),
      );

  static final DownloadStorageMigrationStore instance =
      DownloadStorageMigrationStore();

  final AtomicJsonFile<PendingDownloadStorageMigration> _file;

  Future<void> ensureInitialized() => _file.ensureInitialized();

  Future<PendingDownloadStorageMigration?> read() => _file.read();

  Future<void> write(PendingDownloadStorageMigration migration) =>
      _file.write(migration);

  Future<void> clear() => _file.clear();
}
