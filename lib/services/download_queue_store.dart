import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/services/persistence/atomic_json_file.dart';

enum DownloadQueueTaskStatus { queued, parsing, downloading, paused, failed }

DownloadQueueTaskStatus _taskStatusFromJson(String value) {
  return DownloadQueueTaskStatus.values.firstWhere(
    (DownloadQueueTaskStatus status) => status.name == value,
    orElse: () => DownloadQueueTaskStatus.queued,
  );
}

@immutable
class DownloadQueueTask {
  const DownloadQueueTask({
    required this.id,
    required this.comicKey,
    required this.chapterKey,
    required this.comicTitle,
    required this.comicUri,
    required this.coverUrl,
    required this.chapterLabel,
    required this.chapterHref,
    required this.status,
    required this.progressLabel,
    required this.completedImages,
    required this.totalImages,
    required this.createdAt,
    required this.updatedAt,
    this.errorMessage = '',
    this.autoRetryCount = 0,
    this.nextRetryAt,
    this.detailSnapshot,
  });

  factory DownloadQueueTask.fromJson(Map<String, Object?> json) {
    return DownloadQueueTask(
      id: (json['id'] as String?) ?? '',
      comicKey: (json['comicKey'] as String?) ?? '',
      chapterKey: (json['chapterKey'] as String?) ?? '',
      comicTitle: (json['comicTitle'] as String?) ?? '',
      comicUri: (json['comicUri'] as String?) ?? '',
      coverUrl: (json['coverUrl'] as String?) ?? '',
      chapterLabel: (json['chapterLabel'] as String?) ?? '',
      chapterHref: (json['chapterHref'] as String?) ?? '',
      status: _taskStatusFromJson((json['status'] as String?) ?? ''),
      progressLabel: (json['progressLabel'] as String?) ?? '',
      completedImages: (json['completedImages'] as num?)?.toInt() ?? 0,
      totalImages: (json['totalImages'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt:
          DateTime.tryParse((json['updatedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      errorMessage: (json['errorMessage'] as String?) ?? '',
      autoRetryCount: (json['autoRetryCount'] as num?)?.toInt() ?? 0,
      nextRetryAt: DateTime.tryParse((json['nextRetryAt'] as String?) ?? ''),
      detailSnapshot: json['detailSnapshot'] is Map<Object?, Object?>
          ? CachedComicDetailSnapshot.fromJson(
              (json['detailSnapshot'] as Map<Object?, Object?>).map(
                (Object? key, Object? value) => MapEntry(key.toString(), value),
              ),
            )
          : null,
    );
  }

  final String id;
  final String comicKey;
  final String chapterKey;
  final String comicTitle;
  final String comicUri;
  final String coverUrl;
  final String chapterLabel;
  final String chapterHref;
  final DownloadQueueTaskStatus status;
  final String progressLabel;
  final int completedImages;
  final int totalImages;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String errorMessage;
  final int autoRetryCount;
  final DateTime? nextRetryAt;
  final CachedComicDetailSnapshot? detailSnapshot;

  double get fraction {
    if (totalImages <= 0) {
      return status == DownloadQueueTaskStatus.parsing ? 0 : 0;
    }
    final double value = completedImages / totalImages;
    if (value < 0) {
      return 0;
    }
    if (value > 1) {
      return 1;
    }
    return value;
  }

  DownloadQueueTask copyWith({
    String? id,
    String? comicKey,
    String? chapterKey,
    String? comicTitle,
    String? comicUri,
    String? coverUrl,
    String? chapterLabel,
    String? chapterHref,
    DownloadQueueTaskStatus? status,
    String? progressLabel,
    int? completedImages,
    int? totalImages,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? errorMessage,
    int? autoRetryCount,
    DateTime? nextRetryAt,
    bool clearNextRetryAt = false,
    CachedComicDetailSnapshot? detailSnapshot,
  }) {
    return DownloadQueueTask(
      id: id ?? this.id,
      comicKey: comicKey ?? this.comicKey,
      chapterKey: chapterKey ?? this.chapterKey,
      comicTitle: comicTitle ?? this.comicTitle,
      comicUri: comicUri ?? this.comicUri,
      coverUrl: coverUrl ?? this.coverUrl,
      chapterLabel: chapterLabel ?? this.chapterLabel,
      chapterHref: chapterHref ?? this.chapterHref,
      status: status ?? this.status,
      progressLabel: progressLabel ?? this.progressLabel,
      completedImages: completedImages ?? this.completedImages,
      totalImages: totalImages ?? this.totalImages,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      errorMessage: errorMessage ?? this.errorMessage,
      autoRetryCount: autoRetryCount ?? this.autoRetryCount,
      nextRetryAt: clearNextRetryAt ? null : (nextRetryAt ?? this.nextRetryAt),
      detailSnapshot: detailSnapshot ?? this.detailSnapshot,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'comicKey': comicKey,
      'chapterKey': chapterKey,
      'comicTitle': comicTitle,
      'comicUri': comicUri,
      'coverUrl': coverUrl,
      'chapterLabel': chapterLabel,
      'chapterHref': chapterHref,
      'status': status.name,
      'progressLabel': progressLabel,
      'completedImages': completedImages,
      'totalImages': totalImages,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'errorMessage': errorMessage,
      'autoRetryCount': autoRetryCount,
      'nextRetryAt': nextRetryAt?.toIso8601String(),
      'detailSnapshot': detailSnapshot?.toJson(),
    };
  }
}

@immutable
class DownloadQueueSnapshot {
  const DownloadQueueSnapshot({
    this.isPaused = false,
    this.tasks = const <DownloadQueueTask>[],
  });

  factory DownloadQueueSnapshot.fromJson(Map<String, Object?> json) {
    final List<Object?> rawTasks =
        (json['tasks'] as List<Object?>?) ?? const <Object?>[];
    return DownloadQueueSnapshot(
      isPaused: (json['isPaused'] as bool?) ?? false,
      tasks: rawTasks
          .whereType<Map<Object?, Object?>>()
          .map(
            (Map<Object?, Object?> item) => DownloadQueueTask.fromJson(
              item.map(
                (Object? key, Object? value) => MapEntry(key.toString(), value),
              ),
            ),
          )
          .toList(growable: false),
    );
  }

  final bool isPaused;
  final List<DownloadQueueTask> tasks;

  bool get isEmpty => tasks.isEmpty;
  bool get isNotEmpty => tasks.isNotEmpty;
  DownloadQueueTask? get activeTask => tasks.isEmpty ? null : tasks.first;
  int get remainingCount => tasks.length;

  DownloadQueueSnapshot copyWith({
    bool? isPaused,
    List<DownloadQueueTask>? tasks,
  }) {
    return DownloadQueueSnapshot(
      isPaused: isPaused ?? this.isPaused,
      tasks: tasks ?? this.tasks,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'isPaused': isPaused,
      'tasks': tasks.map((DownloadQueueTask task) => task.toJson()).toList(),
    };
  }
}

class DownloadQueueStore {
  DownloadQueueStore({Future<Directory> Function()? directoryProvider})
    : _file = AtomicJsonFile<DownloadQueueSnapshot>(
        directoryProvider: directoryProvider ?? getApplicationSupportDirectory,
        relativePath: 'download_queue/queue.json',
        decode: (Object? json) => DownloadQueueSnapshot.fromJson(
          Map<String, Object?>.from(json as Map),
        ),
        encode: (DownloadQueueSnapshot snapshot) => snapshot.toJson(),
      );

  static final DownloadQueueStore instance = DownloadQueueStore();

  final AtomicJsonFile<DownloadQueueSnapshot> _file;

  Future<void> ensureInitialized() => _file.ensureInitialized();

  Future<DownloadQueueSnapshot> read() async {
    final DownloadQueueSnapshot snapshot =
        await _file.read() ?? const DownloadQueueSnapshot();
    return snapshot.copyWith(tasks: _normalizeTasks(snapshot.tasks));
  }

  Future<void> write(DownloadQueueSnapshot snapshot) => _file.write(snapshot);

  Future<void> clear() => _file.clear();

  List<DownloadQueueTask> _normalizeTasks(List<DownloadQueueTask> tasks) {
    final DateTime now = DateTime.now();
    return tasks
        .where((DownloadQueueTask task) => task.id.isNotEmpty)
        .map((DownloadQueueTask task) {
          if (task.status == DownloadQueueTaskStatus.parsing ||
              task.status == DownloadQueueTaskStatus.downloading ||
              task.status == DownloadQueueTaskStatus.paused) {
            return task.copyWith(
              status: DownloadQueueTaskStatus.queued,
              updatedAt: now,
            );
          }
          return task;
        })
        .toList(growable: false);
  }
}
