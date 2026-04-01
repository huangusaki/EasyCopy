import 'dart:convert';
import 'dart:io';

import 'package:easy_copy/models/app_preferences.dart';
import 'package:path_provider/path_provider.dart';

typedef DownloadStorageMigrationDirectoryProvider =
    Future<Directory> Function();

class PendingDownloadStorageMigration {
  const PendingDownloadStorageMigration({
    required this.from,
    required this.to,
    required this.createdAt,
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
    );
  }

  final DownloadPreferences from;
  final DownloadPreferences to;
  final DateTime createdAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'from': from.toJson(),
      'to': to.toJson(),
      'createdAt': createdAt.toIso8601String(),
    };
  }
}

class DownloadStorageMigrationStore {
  DownloadStorageMigrationStore({
    DownloadStorageMigrationDirectoryProvider? directoryProvider,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static final DownloadStorageMigrationStore instance =
      DownloadStorageMigrationStore();

  final DownloadStorageMigrationDirectoryProvider _directoryProvider;

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
