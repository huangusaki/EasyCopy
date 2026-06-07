part of '../download_management_page.dart';

class _CachedLibrarySection extends StatefulWidget {
  const _CachedLibrarySection({
    required this.comics,
    required this.onOpenCachedComic,
    required this.onDeleteCachedComic,
  });

  final List<CachedComicLibraryEntry> comics;
  final ValueChanged<CachedComicLibraryEntry> onOpenCachedComic;
  final ValueChanged<CachedComicLibraryEntry> onDeleteCachedComic;

  @override
  State<_CachedLibrarySection> createState() => _CachedLibrarySectionState();
}

class _CachedLibrarySectionState extends State<_CachedLibrarySection> {
  static const int _collapsedLimit = 8;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final List<CachedComicLibraryEntry> comics = widget.comics;
    if (comics.isEmpty) {
      return const AppSurfaceCard(title: '已缓存', child: Text('还没有已缓存漫画。'));
    }
    final bool canCollapse = comics.length > _collapsedLimit;
    final List<CachedComicLibraryEntry> visibleComics =
        canCollapse && !_expanded
        ? comics.take(_collapsedLimit).toList(growable: false)
        : comics;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      title: '已缓存',
      action: Text(
        '共 ${comics.length} 部',
        style: TextStyle(
          color: colorScheme.onSurface.withValues(alpha: 0.58),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ...visibleComics.map((CachedComicLibraryEntry entry) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: identical(entry, visibleComics.last) ? 0 : 12,
              ),
              child: _CachedComicRow(
                entry: entry,
                onTap: () => widget.onOpenCachedComic(entry),
                onDelete: () => widget.onDeleteCachedComic(entry),
              ),
            );
          }),
          if (canCollapse) ...<Widget>[
            const SizedBox(height: 12),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _expanded = !_expanded;
                  });
                },
                icon: Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                ),
                label: Text(
                  _expanded
                      ? '收起'
                      : '展开剩余 ${comics.length - _collapsedLimit} 部',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CachedComicRow extends StatelessWidget {
  const _CachedComicRow({
    required this.entry,
    required this.onTap,
    required this.onDelete,
  });

  final CachedComicLibraryEntry entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final String latestChapterTitle = entry.chapters.isEmpty
        ? '暂无章节'
        : entry.chapters.first.chapterTitle;
    final int cachedCount = entry.cachedChapterCount;
    final int totalCount = entry.detailSnapshot?.totalChapterCount ?? 0;
    final bool hasCoverage = totalCount > 0 && totalCount >= cachedCount;
    final bool isPartial = hasCoverage && cachedCount < totalCount;
    final String coverageLabel = hasCoverage
        ? '已缓存 $cachedCount / 共 $totalCount 话'
        : '$cachedCount 话已缓存';
    return Material(
      color: colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      entry.comicTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      latestChapterTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.74),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      coverageLabel,
                      style: TextStyle(
                        color: isPartial
                            ? colorScheme.tertiary
                            : colorScheme.onSurface.withValues(alpha: 0.66),
                        fontWeight: isPartial
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_CachedMenuAction>(
                tooltip: '更多操作',
                onSelected: (_CachedMenuAction action) {
                  if (action == _CachedMenuAction.delete) {
                    onDelete();
                  }
                },
                itemBuilder: (BuildContext context) {
                  return const <PopupMenuEntry<_CachedMenuAction>>[
                    PopupMenuItem<_CachedMenuAction>(
                      value: _CachedMenuAction.delete,
                      child: Text('删除本地缓存'),
                    ),
                  ];
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
