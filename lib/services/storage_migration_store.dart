import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:reader/models/app_preferences.dart';

typedef MigrationDirProvider = Future<Directory> Function();

enum DownloadStorageMigrationStep { copying, switching, cleaning }

class PendingDownloadStorageMigration {
  const PendingDownloadStorageMigration({
    required this.from,
    required this.to,
    required this.createdAt,
    required this.storageKey,
    required this.activeStorageKey,
    this.phase = DownloadStorageMigrationStep.copying,
    this.cleanupPending = false,
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
      activeStorageKey: (json['activeStorageKey'] as String?)?.trim() ?? '',
      phase: DownloadStorageMigrationStep.values.firstWhere(
        (DownloadStorageMigrationStep entry) => entry.name == json['phase'],
        orElse: () => DownloadStorageMigrationStep.copying,
      ),
      cleanupPending: (json['cleanupPending'] as bool?) ?? false,
    );
  }

  final DownloadPreferences from;
  final DownloadPreferences to;
  final DateTime createdAt;
  final String storageKey;
  final String activeStorageKey;
  final DownloadStorageMigrationStep phase;
  final bool cleanupPending;

  PendingDownloadStorageMigration copyWith({
    DownloadPreferences? from,
    DownloadPreferences? to,
    DateTime? createdAt,
    String? storageKey,
    String? activeStorageKey,
    DownloadStorageMigrationStep? phase,
    bool? cleanupPending,
  }) {
    return PendingDownloadStorageMigration(
      from: from ?? this.from,
      to: to ?? this.to,
      createdAt: createdAt ?? this.createdAt,
      storageKey: storageKey ?? this.storageKey,
      activeStorageKey: activeStorageKey ?? this.activeStorageKey,
      phase: phase ?? this.phase,
      cleanupPending: cleanupPending ?? this.cleanupPending,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'from': from.toJson(),
      'to': to.toJson(),
      'createdAt': createdAt.toIso8601String(),
      'storageKey': storageKey,
      'activeStorageKey': activeStorageKey,
      'phase': phase.name,
      'cleanupPending': cleanupPending,
    };
  }
}

class DownloadStorageMigrationStore {
  DownloadStorageMigrationStore({MigrationDirProvider? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static final DownloadStorageMigrationStore instance =
      DownloadStorageMigrationStore();

  final MigrationDirProvider _directoryProvider;

  Future<void>? _initialization;
  File? _file;

  Future<void> ensureInitialized() {
    return _initialization ??= _initialize();
  }

  Future<PendingDownloadStorageMigration?> read() async {
    await ensureInitialized();
    final File file = _file!;
    if (!await file.exists()) {
      return null;
    }
    try {
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return null;
      }
      return PendingDownloadStorageMigration.fromJson(
        decoded.map(
          (Object? key, Object? value) => MapEntry(key.toString(), value),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> write(PendingDownloadStorageMigration migration) async {
    await ensureInitialized();
    final File file = _file!;
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(migration.toJson()),
      flush: true,
    );
  }

  Future<void> clear() async {
    await ensureInitialized();
    final File file = _file!;
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> _initialize() async {
    final Directory directory = await _directoryProvider();
    final Directory stateDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}download_queue',
    );
    await stateDirectory.create(recursive: true);
    _file = File(
      '${stateDirectory.path}${Platform.pathSeparator}storage_migration.json',
    );
  }
}
