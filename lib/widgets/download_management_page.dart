import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:reader/services/comic_download_service.dart';
import 'package:reader/services/download_queue_store.dart';
import 'package:reader/services/download_storage_service.dart';
import 'package:reader/widgets/responsive_layout.dart';
import 'package:reader/widgets/settings_ui.dart';
import 'package:reader/widgets/top_notice.dart';

part 'download_management_page/cached_library_section.dart';
part 'download_management_page/queue_section.dart';
part 'download_management_page/storage_section.dart';

class DownloadManagementEntryCard extends StatelessWidget {
  const DownloadManagementEntryCard({
    required this.statusLabel,
    required this.queueLabel,
    required this.onTap,
    this.noteLabel,
    super.key,
  });

  final String statusLabel;
  final String queueLabel;
  final String? noteLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      title: '下载管理',
      action: Text(
        '状态 $statusLabel · 队列 $queueLabel',
        style: TextStyle(
          color: colorScheme.onSurface.withValues(alpha: 0.58),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (noteLabel != null && noteLabel!.trim().isNotEmpty) ...<Widget>[
            _InfoRow(
              icon: Icons.sync_rounded,
              text: noteLabel!,
              color: colorScheme.secondary,
            ),
            const SizedBox(height: 16),
          ] else
            const SizedBox(height: 2),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: onTap,
              icon: const Icon(Icons.download_rounded),
              label: const Text('打开下载管理'),
            ),
          ),
        ],
      ),
    );
  }
}

class DownloadManagementPage extends StatefulWidget {
  const DownloadManagementPage({
    required this.queueListenable,
    required this.storageStateListenable,
    required this.storageBusyListenable,
    required this.migrationProgressListenable,
    required this.cachedComics,
    required this.onOpenCachedComic,
    required this.onDeleteCachedComic,
    required this.supportsCustomDirs,
    required this.onPauseQueue,
    required this.onResumeQueue,
    required this.onClearQueue,
    required this.onStopComicTasks,
    required this.onRemoveComic,
    required this.onRemoveTask,
    required this.onRetryTask,
    this.onPickStorageDirectory,
    this.onResetStorageDirectory,
    this.onRescanStorageDirectory,
    super.key,
  });

  final ValueListenable<DownloadQueueSnapshot> queueListenable;
  final ValueListenable<DownloadStorageState> storageStateListenable;
  final ValueListenable<bool> storageBusyListenable;
  final ValueListenable<StorageMigrationProgress?> migrationProgressListenable;
  final List<CachedComicLibraryEntry> cachedComics;
  final ValueChanged<CachedComicLibraryEntry> onOpenCachedComic;
  final ValueChanged<CachedComicLibraryEntry> onDeleteCachedComic;
  final bool supportsCustomDirs;
  final VoidCallback onPauseQueue;
  final VoidCallback onResumeQueue;
  final VoidCallback onClearQueue;
  final ValueChanged<DownloadQueueTask> onStopComicTasks;
  final ValueChanged<DownloadQueueTask> onRemoveComic;
  final ValueChanged<DownloadQueueTask> onRemoveTask;
  final ValueChanged<DownloadQueueTask> onRetryTask;
  final VoidCallback? onPickStorageDirectory;
  final VoidCallback? onResetStorageDirectory;
  final AsyncValueGetter<String>? onRescanStorageDirectory;

  @override
  State<DownloadManagementPage> createState() => _DownloadManagementPageState();
}

class _DownloadManagementPageState extends State<DownloadManagementPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: opaquePageBackground(context),
      appBar: AppBar(title: const Text('下载管理')),
      body: SafeArea(
        child: ValueListenableBuilder<DownloadQueueSnapshot>(
          valueListenable: widget.queueListenable,
          builder:
              (
                BuildContext context,
                DownloadQueueSnapshot snapshot,
                Widget? _,
              ) {
                return ValueListenableBuilder<DownloadStorageState>(
                  valueListenable: widget.storageStateListenable,
                  builder:
                      (
                        BuildContext context,
                        DownloadStorageState storageState,
                        Widget? _,
                      ) {
                        return ValueListenableBuilder<bool>(
                          valueListenable: widget.storageBusyListenable,
                          builder:
                              (
                                BuildContext context,
                                bool storageBusy,
                                Widget? _,
                              ) {
                                return ValueListenableBuilder<
                                  StorageMigrationProgress?
                                >(
                                  valueListenable:
                                      widget.migrationProgressListenable,
                                  builder:
                                      (
                                        BuildContext context,
                                        StorageMigrationProgress?
                                        migrationProgress,
                                        Widget? _,
                                      ) {
                                        final Map<
                                          String,
                                          CachedComicLibraryEntry
                                        >
                                        cachedComicMap = _cachedComicMap(
                                          widget.cachedComics,
                                        );
                                        Widget content = ListView(
                                          padding: const EdgeInsets.fromLTRB(
                                            16,
                                            16,
                                            16,
                                            28,
                                          ),
                                          children: <Widget>[
                                            _CurrentTaskSection(
                                              snapshot: snapshot,
                                              onPauseQueue: widget.onPauseQueue,
                                              onResumeQueue:
                                                  widget.onResumeQueue,
                                            ),
                                            const SizedBox(height: 16),
                                            _QueueSection(
                                              snapshot: snapshot,
                                              cachedComicMap: cachedComicMap,
                                              onClearQueue: widget.onClearQueue,
                                              onStopComicTasks:
                                                  widget.onStopComicTasks,
                                              onRemoveComic:
                                                  widget.onRemoveComic,
                                              onRemoveTask: widget.onRemoveTask,
                                              onRetryTask: widget.onRetryTask,
                                            ),
                                            const SizedBox(height: 16),
                                            _CachedLibrarySection(
                                              comics: widget.cachedComics,
                                              onOpenCachedComic:
                                                  widget.onOpenCachedComic,
                                              onDeleteCachedComic:
                                                  widget.onDeleteCachedComic,
                                            ),
                                            const SizedBox(height: 16),
                                            _StorageSection(
                                              state: storageState,
                                              busy: storageBusy,
                                              migrationProgress:
                                                  migrationProgress,
                                              supportsCustomDirs:
                                                  widget.supportsCustomDirs,
                                              onPickStorageDirectory:
                                                  widget.onPickStorageDirectory,
                                              onResetStorageDirectory: widget
                                                  .onResetStorageDirectory,
                                              onRescanStorageDirectory: widget
                                                  .onRescanStorageDirectory,
                                            ),
                                          ],
                                        );
                                        if (usesWideLayout(context)) {
                                          content = Align(
                                            alignment: Alignment.topCenter,
                                            child: ConstrainedBox(
                                              constraints: const BoxConstraints(
                                                maxWidth: 920,
                                              ),
                                              child: content,
                                            ),
                                          );
                                        }
                                        return content;
                                      },
                                );
                              },
                        );
                      },
                );
              },
        ),
      ),
    );
  }
}
