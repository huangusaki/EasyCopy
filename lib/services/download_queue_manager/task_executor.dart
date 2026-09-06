import 'package:reader/models/page_models.dart';
import 'package:reader/services/comic_download_service/download_contracts.dart';
import 'package:reader/services/download_queue_store.dart';

abstract class DownloadTaskRunner {
  Future<ReaderPageData> prepare(DownloadQueueTask task);

  Future<void> download(
    DownloadQueueTask task,
    ReaderPageData page, {
    required ChapterDownloadPauseChecker shouldPause,
    required ChapterDownloadCancelChecker shouldCancel,
    ChapterDownloadProgressCallback? onProgress,
  });
}

/// A lease on one queue generation. Removed or replaced tasks lose this lease.
abstract interface class DownloadTaskExecutionHost {
  DownloadQueueTask? get currentTask;
  bool get shouldPause;
  bool get shouldCancel;
  Future<void> update(DownloadQueueTask task, {bool persist = true});
}

enum DownloadTaskOutcome { completed, paused, cancelled, failed }

class DownloadTaskExecutionResult {
  const DownloadTaskExecutionResult(this.outcome, {this.error});

  final DownloadTaskOutcome outcome;
  final Object? error;
}

/// Executes one attempt; scheduling, retries, cleanup and storage stay outside.
class DownloadTaskExecutor {
  DownloadTaskExecutor({
    required DownloadTaskRunner runner,
    DateTime Function()? now,
  }) : _runner = runner,
       _now = now ?? DateTime.now;

  final DownloadTaskRunner _runner;
  final DateTime Function() _now;

  Future<DownloadTaskExecutionResult> execute(
    DownloadQueueTask task,
    DownloadTaskExecutionHost host,
  ) async {
    bool finished = false;
    void checkControl() {
      if (host.shouldCancel) throw const DownloadCancelledException();
      if (host.shouldPause) throw const DownloadPausedException();
    }

    try {
      checkControl();
      await host.update(
        task.copyWith(
          status: DownloadQueueTaskStatus.parsing,
          progressLabel: '正在解析 ${task.chapterLabel}',
          completedImages: 0,
          totalImages: 0,
          errorMessage: '',
          updatedAt: _now(),
        ),
      );
      checkControl();
      final ReaderPageData page = await _runner.prepare(task);
      checkControl();
      await host.update(
        task.copyWith(
          status: DownloadQueueTaskStatus.downloading,
          progressLabel: '正在缓存 ${task.chapterLabel}',
          completedImages: 0,
          totalImages: page.imageUrls.length,
          errorMessage: '',
          updatedAt: _now(),
        ),
      );
      checkControl();
      await _runner.download(
        task,
        page,
        shouldPause: () => host.shouldPause,
        shouldCancel: () => finished || host.shouldCancel,
        onProgress: (ChapterDownloadProgress progress) async {
          if (finished || host.shouldCancel || host.shouldPause) return;
          final DownloadQueueTask? current = host.currentTask;
          if (current == null) return;
          await host.update(
            current.copyWith(
              status: DownloadQueueTaskStatus.downloading,
              progressLabel: '${task.chapterLabel} · ${progress.currentLabel}',
              completedImages: progress.completedCount,
              totalImages: progress.totalCount,
              errorMessage: '',
              updatedAt: _now(),
            ),
            persist: false,
          );
        },
      );
      checkControl();
      return const DownloadTaskExecutionResult(DownloadTaskOutcome.completed);
    } on DownloadPausedException {
      return DownloadTaskExecutionResult(
        host.shouldCancel
            ? DownloadTaskOutcome.cancelled
            : DownloadTaskOutcome.paused,
      );
    } on DownloadCancelledException {
      return const DownloadTaskExecutionResult(DownloadTaskOutcome.cancelled);
    } catch (error) {
      return DownloadTaskExecutionResult(
        host.shouldCancel
            ? DownloadTaskOutcome.cancelled
            : host.shouldPause
            ? DownloadTaskOutcome.paused
            : DownloadTaskOutcome.failed,
        error: error,
      );
    } finally {
      finished = true;
    }
  }
}
