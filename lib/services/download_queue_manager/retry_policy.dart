import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:reader/services/comic_download_service/download_contracts.dart';
import 'package:reader/services/download_queue_store.dart';

class DownloadRetryPolicy {
  const DownloadRetryPolicy({
    this.delay = const Duration(seconds: 5),
    this.maxRetries = 3,
  }) : assert(maxRetries >= 0);

  final Duration delay;
  final int maxRetries;

  DownloadQueueTask failedTask(
    DownloadQueueTask task,
    Object error,
    DateTime now,
  ) {
    final String message = formatDownloadError(error);
    final bool retry = task.autoRetryCount < maxRetries;
    final int count = retry ? task.autoRetryCount + 1 : task.autoRetryCount;
    return task.copyWith(
      status: DownloadQueueTaskStatus.failed,
      progressLabel: retry
          ? '失败，${delay.inSeconds}秒后重试（$count/$maxRetries）'
          : '失败：$message',
      errorMessage: message,
      autoRetryCount: count,
      nextRetryAt: retry ? now.add(delay) : null,
      clearNextRetryAt: !retry,
      updatedAt: now,
    );
  }

  DownloadQueueTask queuedTask(
    DownloadQueueTask task,
    DateTime now, {
    bool resetAttempts = false,
  }) {
    return task.copyWith(
      status: DownloadQueueTaskStatus.queued,
      progressLabel: '等待缓存',
      errorMessage: '',
      completedImages: 0,
      totalImages: 0,
      autoRetryCount: resetAttempts ? 0 : task.autoRetryCount,
      clearNextRetryAt: true,
      updatedAt: now,
    );
  }
}

/// Owns retry timers only; the queue revalidates task identity when they fire.
class DownloadRetryScheduler {
  DownloadRetryScheduler({
    required Future<void> Function(String) onReady,
    DateTime Function()? now,
  }) : _onReady = onReady,
       _now = now ?? DateTime.now;

  final Future<void> Function(String) _onReady;
  final DateTime Function() _now;
  final Map<String, Timer> _timers = <String, Timer>{};
  final Map<String, DateTime> _deadlines = <String, DateTime>{};
  bool _disposed = false;

  void sync(DownloadQueueSnapshot snapshot) {
    final Map<String, DateTime> deadlines = <String, DateTime>{
      if (!snapshot.isPaused)
        for (final DownloadQueueTask task in snapshot.tasks)
          if (task.status == DownloadQueueTaskStatus.failed &&
              task.nextRetryAt != null)
            task.id: task.nextRetryAt!,
    };
    for (final String id in _timers.keys.toList()) {
      if (deadlines[id] != _deadlines[id]) cancel(id);
    }
    if (_disposed) return;
    deadlines.forEach((String id, DateTime deadline) {
      if (_timers.containsKey(id)) return;
      _deadlines[id] = deadline;
      final Duration delay = deadline.difference(_now());
      _timers[id] = Timer(delay.isNegative ? Duration.zero : delay, () {
        _timers.remove(id);
        _deadlines.remove(id);
        if (!_disposed) unawaited(_onReady(id));
      });
    });
  }

  void cancel(String id) {
    _timers.remove(id)?.cancel();
    _deadlines.remove(id);
  }

  void dispose() {
    _disposed = true;
    for (final String id in _timers.keys.toList()) {
      cancel(id);
    }
  }
}

String formatDownloadError(Object error) {
  return switch (error) {
    TimeoutException _ => '章节解析超时',
    HttpException error => error.message,
    FileSystemException error => error.message,
    PlatformException error =>
      error.message?.trim().isNotEmpty == true
          ? error.message!.trim()
          : error.code,
    DownloadPausedException error => error.message,
    DownloadCancelledException error => error.message,
    _ => error.toString(),
  };
}
