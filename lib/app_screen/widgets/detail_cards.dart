// ignore_for_file: use_key_in_widget_constructors

part of '../widgets.dart';

class DetailHeroCard extends StatelessWidget {
  const DetailHeroCard({
    required this.page,
    required this.onReadNow,
    required this.onDownload,
    required this.onToggleCollection,
    required this.isCollectionBusy,
    required this.onTagTap,
    required this.onAuthorTap,
  });

  final DetailPageData page;
  final VoidCallback? onReadNow;
  final VoidCallback? onDownload;
  final VoidCallback? onToggleCollection;
  final bool isCollectionBusy;
  final ValueChanged<String> onTagTap;
  final ValueChanged<String> onAuthorTap;

  List<String> _searchLabels(String value) {
    final List<String> labels = <String>[];
    for (final String segment in value.split(RegExp(r'\s*[\/／]\s*'))) {
      final String normalized = segment.trim();
      if (normalized.isEmpty || labels.contains(normalized)) {
        continue;
      }
      labels.add(normalized);
    }
    if (labels.isEmpty && value.trim().isNotEmpty) {
      labels.add(value.trim());
    }
    return labels;
  }

  @override
  Widget build(BuildContext context) {
    final List<String> authorLabels = _searchLabels(page.authors);
    return AppSurfaceCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 122,
                child: CoverImage(imageUrl: page.coverUrl, aspectRatio: 0.72),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      page.title,
                      style: const TextStyle(
                        fontSize: 24,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (page.authorLinks.isNotEmpty ||
                        authorLabels.isNotEmpty ||
                        page.tags.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          if (page.authorLinks.isNotEmpty)
                            ...page.authorLinks.map(
                              (LinkAction author) => LinkChip(
                                label: author.label,
                                active: true,
                                onTap: () => onAuthorTap(author.href),
                              ),
                            )
                          else
                            ...authorLabels.map(
                              (String author) => LinkChip(
                                label: author,
                                active: true,
                                onTap: () => onTagTap(author),
                              ),
                            ),
                          ...page.tags
                              .take(6)
                              .map(
                                (LinkAction tag) => LinkChip(
                                  label: tag.label,
                                  active: true,
                                  onTap: () => onTagTap(tag.label),
                                ),
                              ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: onReadNow,
                  icon: const Icon(Icons.chrome_reader_mode_rounded),
                  label: const Text('开始阅读'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: isCollectionBusy ? null : onToggleCollection,
                  icon: isCollectionBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          page.isCollected
                              ? Icons.bookmark_remove_rounded
                              : Icons.bookmark_add_rounded,
                        ),
                  label: Text(page.isCollected ? '取消收藏' : '加入书架'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: onDownload,
              icon: const Icon(Icons.download_rounded),
              label: const Text('缓存章节'),
            ),
          ),
        ],
      ),
    );
  }
}

class InfoChip extends StatelessWidget {
  const InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 132),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.62),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class ChapterGrid extends StatelessWidget {
  const ChapterGrid({
    required this.chapters,
    required this.onTap,
    this.downloadedChapterPathKeys = const <String>{},
    this.lastReadChapterPathKey = '',
    this.itemKeyBuilder,
  });

  final List<ChapterData> chapters;
  final ValueChanged<String> onTap;
  final Set<String> downloadedChapterPathKeys;
  final String lastReadChapterPathKey;
  final GlobalKey Function(String chapterPathKey)? itemKeyBuilder;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final AppSemanticColors semanticColors = theme
        .extension<AppSemanticColors>()!;
    final Color lastReadColor = colorScheme.primary;
    final Color onLastReadColor = colorScheme.onPrimary;
    final Color lastReadBorderColor = Color.alphaBlend(
      Colors.black.withValues(alpha: 0.18),
      colorScheme.primary,
    );
    final Color downloadedColor = semanticColors.success;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: chapters.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.7,
      ),
      itemBuilder: (BuildContext context, int index) {
        final ChapterData chapter = chapters[index];
        final String chapterPathKey = Uri.tryParse(chapter.href) == null
            ? ''
            : Uri(path: Uri.parse(chapter.href).path).toString();
        final bool isDownloaded = downloadedChapterPathKeys.contains(
          chapterPathKey,
        );
        final bool isLastRead =
            lastReadChapterPathKey.isNotEmpty &&
            chapterPathKey == lastReadChapterPathKey;
        final Widget child = InkWell(
          onTap: () => onTap(chapter.href),
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isLastRead
                  ? lastReadColor
                  : isDownloaded
                  ? colorScheme.primaryContainer.withValues(alpha: 0.38)
                  : colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(18),
              border: isLastRead
                  ? Border.all(color: lastReadBorderColor, width: 1.2)
                  : isDownloaded
                  ? Border.all(color: downloadedColor)
                  : null,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    chapter.label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.1,
                      fontWeight: FontWeight.w800,
                      color: isLastRead ? onLastReadColor : null,
                    ),
                  ),
                ),
                if (isLastRead || isDownloaded) ...<Widget>[
                  const SizedBox(width: 4),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      if (isLastRead)
                        Icon(
                          Icons.bookmark_rounded,
                          size: 13,
                          color: onLastReadColor,
                        ),
                      if (isDownloaded) ...<Widget>[
                        if (isLastRead) const SizedBox(height: 3),
                        Icon(
                          Icons.check_circle_rounded,
                          size: 13,
                          color: downloadedColor,
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
        final GlobalKey? itemKey = itemKeyBuilder?.call(chapterPathKey);
        return itemKey == null
            ? child
            : KeyedSubtree(key: itemKey, child: child);
      },
    );
  }
}
