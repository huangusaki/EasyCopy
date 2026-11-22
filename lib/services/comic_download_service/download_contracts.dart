import 'dart:io';

typedef ChapterDownloadProgressCallback =
    Future<void> Function(ChapterDownloadProgress progress);
typedef ChapterDownloadPauseChecker = bool Function();
typedef ChapterDownloadCancelChecker = bool Function();

class ChapterDownloadProgress {
  const ChapterDownloadProgress({
    required this.completedCount,
    required this.totalCount,
    required this.currentLabel,
  });

  final int completedCount;
  final int totalCount;
  final String currentLabel;
}

class DownloadPausedException implements Exception {
  const DownloadPausedException([this.message = '缓存已暂停。']);

  final String message;

  @override
  String toString() => message;
}

class DownloadCancelledException implements Exception {
  const DownloadCancelledException([this.message = '缓存任务已取消。']);

  final String message;

  @override
  String toString() => message;
}

class LocalChapterChangedException extends FileSystemException {
  const LocalChapterChangedException() : super('本地章节缓存已变化，请重试下载。');
}
