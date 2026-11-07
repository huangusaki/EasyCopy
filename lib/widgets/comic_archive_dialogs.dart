import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:reader/services/comic_archive.dart';

Future<ComicArchivePreview?> showComicArchivePreview(
  BuildContext context,
  ComicArchivePreview preview, {
  required String archivePath,
}) async {
  final GlobalKey<_ArchivePreviewDialogState> key = GlobalKey();
  try {
    return await showDialog<ComicArchivePreview>(
      context: context,
      builder: (_) => _ArchivePreviewDialog(
        key: key,
        preview: preview,
        archivePath: archivePath,
      ),
    );
  } finally {
    await key.currentState?._finishPreview();
  }
}

class _ArchivePreviewDialog extends StatefulWidget {
  const _ArchivePreviewDialog({
    required this.preview,
    required this.archivePath,
    super.key,
  });

  final ComicArchivePreview preview;
  final String archivePath;

  @override
  State<_ArchivePreviewDialog> createState() => _ArchivePreviewDialogState();
}

class _ArchivePreviewDialogState extends State<_ArchivePreviewDialog> {
  late final TextEditingController _title = TextEditingController(
    text: widget.preview.title,
  );
  late final List<ComicArchiveChapter> _chapters = List.of(
    widget.preview.chapters,
  );
  Directory? _previewDirectory;
  Future<void> _coverTask = Future<void>.value();
  Future<void>? _cleanupTask;
  String? _coverEntry;
  String? _coverPath;
  bool _coverFailed = false;
  int _coverGeneration = 0;

  @override
  void initState() {
    super.initState();
    _requestCover();
  }

  @override
  void dispose() {
    unawaited(_finishPreview());
    _title.dispose();
    super.dispose();
  }

  void _requestCover() {
    final String entry = _chapters.first.entries.first;
    if (_coverEntry == entry) return;
    _coverEntry = entry;
    _coverPath = null;
    _coverFailed = false;
    final int generation = ++_coverGeneration;
    _coverTask = _coverTask.then((_) => _loadCover(entry, generation));
  }

  Future<void> _loadCover(String entry, int generation) async {
    if (!mounted || generation != _coverGeneration) return;
    try {
      _previewDirectory ??= await (await getTemporaryDirectory()).createTemp(
        'comic_archive_preview_',
      );
      final List<ComicArchiveChapterFiles> chapters =
          await ComicArchive.extract(
            widget.archivePath,
            ComicArchivePreview(widget.preview.title, <ComicArchiveChapter>[
              ComicArchiveChapter('cover', <String>[entry]),
            ]),
            '${_previewDirectory!.path}/$generation',
            isCancelled: () => !mounted || generation != _coverGeneration,
          );
      if (mounted && generation == _coverGeneration) {
        setState(() => _coverPath = chapters.single.files.single);
      }
    } on ComicArchiveCancelled {
      // 首图改变或弹窗关闭后，不再提交旧预览。
    } catch (_) {
      if (mounted && generation == _coverGeneration) {
        setState(() => _coverFailed = true);
      }
    }
  }

  Future<void> _clearPreview() async {
    await _coverTask;
    final Directory? directory = _previewDirectory;
    if (directory != null) {
      try {
        await directory.delete(recursive: true);
      } on FileSystemException catch (error) {
        debugPrint('Archive preview cleanup failed: $error');
      }
    }
  }

  Future<void> _finishPreview() {
    if (_cleanupTask != null) return _cleanupTask!;
    _coverGeneration++;
    return _cleanupTask = _clearPreview();
  }

  Future<void> _editChapter(int index) async {
    final ComicArchiveChapter? chapter = await showDialog<ComicArchiveChapter>(
      context: context,
      builder: (_) => _ArchiveChapterDialog(chapter: _chapters[index]),
    );
    if (chapter != null && mounted) {
      setState(() {
        _chapters[index] = chapter;
        _requestCover();
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('导入漫画'),
    scrollable: true,
    content: SizedBox(
      width: 520,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              SizedBox(
                width: 72,
                height: 96,
                child: _coverPath != null
                    ? Image.file(
                        File(_coverPath!),
                        cacheWidth: 144,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.broken_image_outlined),
                      )
                    : Center(
                        child: _coverFailed
                            ? const Icon(Icons.broken_image_outlined)
                            : const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: _title,
                  decoration: const InputDecoration(labelText: '漫画名称'),
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.done,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('${_chapters.length} 章 · ${widget.preview.imageCount} 页'),
          const SizedBox(height: 8),
          SizedBox(
            height: math.min(360, MediaQuery.sizeOf(context).height * 0.4),
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: _chapters.length,
              onReorder: (int oldIndex, int newIndex) {
                setState(() {
                  _reorder(_chapters, oldIndex, newIndex);
                  _requestCover();
                });
              },
              itemBuilder: (BuildContext context, int index) {
                final ComicArchiveChapter chapter = _chapters[index];
                return ListTile(
                  key: ObjectKey(chapter),
                  contentPadding: EdgeInsets.zero,
                  leading: Text('${index + 1}'),
                  title: Text(
                    chapter.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${chapter.entries.length} 页 · ${_fileName(chapter.entries.first)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: _ArchiveDragHandle(index: index),
                  onTap: () => _editChapter(index),
                );
              },
            ),
          ),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _title.text.trim().isEmpty
            ? null
            : () => Navigator.of(context).pop(
                ComicArchivePreview(
                  _title.text.trim(),
                  List.unmodifiable(_chapters),
                ),
              ),
        child: const Text('导入'),
      ),
    ],
  );
}

class _ArchiveChapterDialog extends StatefulWidget {
  const _ArchiveChapterDialog({required this.chapter});

  final ComicArchiveChapter chapter;

  @override
  State<_ArchiveChapterDialog> createState() => _ArchiveChapterDialogState();
}

class _ArchiveChapterDialogState extends State<_ArchiveChapterDialog> {
  late final TextEditingController _title = TextEditingController(
    text: widget.chapter.title,
  );
  late final List<String> _entries = List.of(widget.chapter.entries);

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('页面顺序'),
    scrollable: true,
    content: SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: '章节名称'),
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: math.min(360, MediaQuery.sizeOf(context).height * 0.4),
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              itemCount: _entries.length,
              onReorder: (int oldIndex, int newIndex) {
                setState(() => _reorder(_entries, oldIndex, newIndex));
              },
              itemBuilder: (BuildContext context, int index) => ListTile(
                key: ValueKey(_entries[index]),
                contentPadding: EdgeInsets.zero,
                leading: Text('${index + 1}'),
                title: Text(
                  _fileName(_entries[index]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: _ArchiveDragHandle(index: index),
              ),
            ),
          ),
        ],
      ),
    ),
    actions: <Widget>[
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _title.text.trim().isEmpty
            ? null
            : () => Navigator.of(context).pop(
                ComicArchiveChapter(
                  _title.text.trim(),
                  List.unmodifiable(_entries),
                ),
              ),
        child: const Text('完成'),
      ),
    ],
  );
}

class _ArchiveDragHandle extends StatelessWidget {
  const _ArchiveDragHandle({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) => ReorderableDragStartListener(
    index: index,
    child: const Tooltip(
      message: '调整顺序',
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Icon(Icons.drag_handle_rounded),
      ),
    ),
  );
}

void _reorder<T>(List<T> items, int oldIndex, int newIndex) {
  if (newIndex > oldIndex) newIndex--;
  items.insert(newIndex, items.removeAt(oldIndex));
}

String _fileName(String path) => path.split('/').last;

Future<T> runComicArchiveOperation<T>(
  BuildContext context, {
  required String title,
  required Future<T> Function(
    void Function(int, int) onProgress,
    bool Function() isCancelled,
  )
  operation,
}) async {
  final ValueNotifier<(int, int)> progress = ValueNotifier((0, 0));
  final ValueNotifier<bool> cancelled = ValueNotifier(false);
  final NavigatorState navigator = Navigator.of(context, rootNavigator: true);
  final DialogRoute<void> route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 320,
          child: ValueListenableBuilder<(int, int)>(
            valueListenable: progress,
            builder: (BuildContext context, (int, int) value, Widget? _) =>
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    LinearProgressIndicator(
                      value: value.$2 > 0 ? value.$1 / value.$2 : null,
                    ),
                    if (value.$2 > 0) ...<Widget>[
                      const SizedBox(height: 12),
                      Text('${value.$1} / ${value.$2}'),
                    ],
                  ],
                ),
          ),
        ),
        actions: <Widget>[
          ValueListenableBuilder<bool>(
            valueListenable: cancelled,
            builder: (BuildContext context, bool value, Widget? _) =>
                TextButton(
                  onPressed: value ? null : () => cancelled.value = true,
                  child: Text(value ? '正在取消…' : '取消'),
                ),
          ),
        ],
      ),
    ),
  );
  unawaited(navigator.push(route));
  try {
    return await operation(
      (int completed, int total) => progress.value = (completed, total),
      () => cancelled.value,
    );
  } finally {
    if (route.isActive) navigator.removeRoute(route);
    await route.completed;
    progress.dispose();
    cancelled.dispose();
  }
}
