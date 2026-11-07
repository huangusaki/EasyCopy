part of '../app_screen.dart';

extension _AppScreenArchiveActions on _AppScreenState {
  Future<void> _importComicArchive() async {
    if (_archiveDialogOpen) return;
    _archiveDialogOpen = true;
    PickedComicArchive? picked;
    try {
      final ComicArchivePreview? preview = await runComicArchiveOperation(
        context,
        title: '正在读取',
        operation: (onProgress, isCancelled) async {
          picked = await ComicArchiveFiles.pick();
          final PickedComicArchive? source = picked;
          if (source == null) return null;
          if (isCancelled()) throw const ComicArchiveCancelled();
          final ComicArchivePreview preview = await ComicArchive.inspect(
            source.path,
            title: source.name.replaceFirst(
              RegExp(r'\.(zip|cbz)$', caseSensitive: false),
              '',
            ),
          );
          if (isCancelled()) throw const ComicArchiveCancelled();
          return preview;
        },
      );
      if (preview == null || !mounted) return;
      final PickedComicArchive source = picked!;
      final ComicArchivePreview? confirmed = await showComicArchivePreview(
        context,
        preview,
        archivePath: source.path,
      );
      if (confirmed == null || !mounted) return;
      await runComicArchiveOperation(
        context,
        title: '正在导入',
        operation: (onProgress, isCancelled) =>
            _downloadQueueManager.runArchiveOperation(() async {
              await _library.refreshTask;
              return _services.downloadService.importComicArchive(
                source.path,
                confirmed,
                onProgress: onProgress,
                isCancelled: isCancelled,
              );
            }),
      );
      await _refreshCachedComics();
      if (mounted) _showNotice('已导入《${confirmed.title}》');
    } on ComicArchiveCancelled {
      // The operation removes its own unfinished files.
    } catch (error) {
      if (mounted) _showNotice('导入失败：${formatDownloadError(error)}');
    } finally {
      await picked?.dispose();
      _archiveDialogOpen = false;
    }
  }

  Future<void> _exportComicArchive(CachedComicLibraryEntry comic) async {
    if (_archiveDialogOpen) return;
    _archiveDialogOpen = true;
    Directory? temporary;
    try {
      temporary = await Directory.systemTemp.createTemp('easycopy-archive-');
      final String outputPath = '${temporary.path}/comic.zip';
      if (!mounted) return;
      await runComicArchiveOperation(
        context,
        title: '正在导出',
        operation: (onProgress, isCancelled) =>
            _downloadQueueManager.runArchiveOperation(
              () => _services.downloadService.exportComicArchive(
                comic,
                outputPath,
                onProgress: onProgress,
                isCancelled: isCancelled,
              ),
            ),
      );
      if (!mounted) return;
      final String name = _services.downloadService.comicDirectoryPath(
        comic.comicTitle,
      );
      if (await ComicArchiveFiles.save(outputPath, '$name.zip') && mounted) {
        _showNotice('导出完成');
      }
    } on ComicArchiveCancelled {
      // Cancelled exports only leave a temporary file, removed below.
    } catch (error) {
      if (mounted) _showNotice('导出失败：${formatDownloadError(error)}');
    } finally {
      await temporary?.delete(recursive: true);
      _archiveDialogOpen = false;
    }
  }
}
