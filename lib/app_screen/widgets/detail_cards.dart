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
    if (usesDesktopLayout(context)) {
      return _buildDesktopHero(context, authorLabels);
    }
    return _buildMobileCard(context, authorLabels);
  }

  Widget _buildDesktopHero(BuildContext context, List<String> authorLabels) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Stack(
        children: <Widget>[
          Positioned.fill(child: _BlurredCoverBanner(coverUrl: page.coverUrl)),
          Padding(
            padding: const EdgeInsets.all(26),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _HoverFloatCover(coverUrl: page.coverUrl),
                const SizedBox(width: 26),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        page.title,
                        style: TextStyle(
                          fontSize: 27,
                          height: 1.15,
                          fontWeight: FontWeight.w900,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      if (_hasCreditChips(authorLabels)) ...<Widget>[
                        const SizedBox(height: 14),
                        _buildCreditChips(authorLabels),
                      ],
                      const SizedBox(height: 22),
                      Row(
                        children: <Widget>[
                          FilledButton.icon(
                            onPressed: onReadNow,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 26,
                                vertical: 16,
                              ),
                            ),
                            icon: const Icon(Icons.chrome_reader_mode_rounded),
                            label: const Text('开始阅读'),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.tonalIcon(
                            onPressed: isCollectionBusy
                                ? null
                                : onToggleCollection,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 16,
                              ),
                            ),
                            icon: _buildCollectionIcon(),
                            label: Text(page.isCollected ? '取消收藏' : '加入书架'),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.tonalIcon(
                            onPressed: onDownload,
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 16,
                              ),
                            ),
                            icon: const Icon(Icons.download_rounded),
                            label: const Text('缓存章节'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileCard(BuildContext context, List<String> authorLabels) {
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
                    if (_hasCreditChips(authorLabels)) ...<Widget>[
                      const SizedBox(height: 14),
                      _buildCreditChips(authorLabels),
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
                  icon: _buildCollectionIcon(),
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

  bool _hasCreditChips(List<String> authorLabels) {
    return page.authorLinks.isNotEmpty ||
        authorLabels.isNotEmpty ||
        page.tags.isNotEmpty;
  }

  Widget _buildCreditChips(List<String> authorLabels) {
    return Wrap(
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
        ...page.tags.map(
          (LinkAction tag) => LinkChip(
            label: tag.label,
            active: true,
            onTap: tag.href.trim().isEmpty
                ? () => onTagTap(tag.label)
                : () => onAuthorTap(tag.href),
          ),
        ),
      ],
    );
  }

  Widget _buildCollectionIcon() {
    if (isCollectionBusy) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Icon(
      page.isCollected
          ? Icons.bookmark_remove_rounded
          : Icons.bookmark_add_rounded,
    );
  }
}

class _BlurredCoverBanner extends StatelessWidget {
  const _BlurredCoverBanner({required this.coverUrl});

  final String coverUrl;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          RepaintBoundary(
            child: Transform.scale(
              scale: 1.5,
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 42, sigmaY: 42),
                child: CoverImage(
                  imageUrl: coverUrl,
                  borderRadius: 0,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  colorScheme.surface.withValues(alpha: 0.78),
                  colorScheme.surface.withValues(alpha: 0.94),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HoverFloatCover extends StatefulWidget {
  const _HoverFloatCover({required this.coverUrl});

  final String coverUrl;

  @override
  State<_HoverFloatCover> createState() => _HoverFloatCoverState();
}

class _HoverFloatCoverState extends State<_HoverFloatCover> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        width: 196,
        transform: _isHovered
            ? (Matrix4.identity()..translateByDouble(0, -6, 0, 1))
            : Matrix4.identity(),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: _isHovered ? 0.30 : 0.20),
              blurRadius: _isHovered ? 34 : 24,
              offset: Offset(0, _isHovered ? 16 : 10),
            ),
          ],
        ),
        child: CoverImage(imageUrl: widget.coverUrl, aspectRatio: 0.72),
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
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final bool isDesktop = usesDesktopLayout(context);
        final int crossAxisCount = responsiveComicCrossAxisCount(
          context,
          maxWidth,
          minItemWidth: 132,
          spacing: 10,
          maxCount: 6,
        );
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: chapters.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: isDesktop ? 2.35 : 1.7,
          ),
          itemBuilder: (BuildContext context, int index) {
            final ChapterData chapter = chapters[index];
            final Uri? chapterUri = Uri.tryParse(chapter.href);
            final String chapterPathKey = chapterUri == null
                ? ''
                : Uri(path: chapterUri.path).toString();
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
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
      },
    );
  }
}
