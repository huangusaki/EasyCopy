class DownloadChapterEnqueueResult {
  const DownloadChapterEnqueueResult({
    required this.addedCount,
    required this.skippedCachedCount,
    required this.skippedQueuedCount,
  });

  final int addedCount;
  final int skippedCachedCount;
  final int skippedQueuedCount;

  bool get hasAddedTasks => addedCount > 0;

  String failureNotice() {
    if (skippedCachedCount > 0 && skippedQueuedCount > 0) {
      return '所选章节已缓存或已在队列中';
    }
    if (skippedCachedCount > 0) {
      return '所选章节都已经缓存过了';
    }
    return '所选章节已在后台缓存队列中';
  }

  String successNotice({required bool keepPaused}) {
    final StringBuffer message = StringBuffer('已加入后台缓存队列：$addedCount 话');
    if (skippedCachedCount > 0) {
      message.write('，已跳过已缓存 $skippedCachedCount 话');
    }
    if (skippedQueuedCount > 0) {
      message.write('，已跳过队列内 $skippedQueuedCount 话');
    }
    if (keepPaused) {
      message.write('（当前队列已暂停）');
    }
    return message.toString();
  }
}
