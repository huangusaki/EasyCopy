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
    if (usesWideLayout(context)) {
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
                      _AdaptiveTitle(
                        text: page.title,
                        fontSizes: const <double>[27, 23, 20],
                        lineHeight: 1.15,
                        color: colorScheme.onSurface,
                      ),
                      ..._buildTitleMeta(context, authorLabels),
                      if (page.summary.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 16),
                        _buildSummary(),
                      ],
                      if (page.tags.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 14),
                        _buildTagChips(),
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
        crossAxisAlignment: CrossAxisAlignment.start,
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
                    _AdaptiveTitle(
                      text: page.title,
                      fontSizes: const <double>[24, 20, 17],
                      lineHeight: 1.15,
                    ),
                    ..._buildTitleMeta(context, authorLabels),
                  ],
                ),
              ),
            ],
          ),
          // 简介与标签排在整行下面，跟着封面右侧那列走会在封面下方留出空白。
          if (page.summary.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            _buildSummary(),
          ],
          if (page.tags.isNotEmpty) ...<Widget>[
            const SizedBox(height: 14),
            _buildTagChips(),
          ],
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

  List<Widget> _buildTitleMeta(
    BuildContext context,
    List<String> authorLabels,
  ) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final List<String> metaParts = <String>[
      if (page.status.isNotEmpty) page.status,
      if (page.updatedAt.isNotEmpty) '更新 ${page.updatedAt}',
    ];
    final List<Widget> authorChips = <Widget>[
      if (page.authorLinks.isNotEmpty)
        for (final LinkAction author in page.authorLinks)
          _buildAuthorChip(
            context,
            label: author.label,
            onTap: () => onAuthorTap(author.href),
          )
      else
        for (final String author in authorLabels)
          _buildAuthorChip(
            context,
            label: author,
            onTap: () => onTagTap(author),
          ),
    ];
    return <Widget>[
      if (metaParts.isNotEmpty) ...<Widget>[
        const SizedBox(height: 10),
        Text(
          ChineseConverter.instance.convert(metaParts.join('  ·  ')),
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: colorScheme.onSurface.withValues(alpha: 0.68),
          ),
        ),
      ],
      // 作者单独占一行：仍是可点的 chip，但用 primary 色系和人像图标跟题材标签区分。
      if (authorChips.isNotEmpty) ...<Widget>[
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: authorChips),
      ],
    ];
  }

  Widget _buildAuthorChip(
    BuildContext context, {
    required String label,
    required VoidCallback onTap,
  }) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 13, 6),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.person_rounded,
              size: 13,
              color: colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 5),
            Text(
              ChineseConverter.instance.convert(label),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary() {
    return Text(
      ChineseConverter.instance.convert(page.summary),
      style: const TextStyle(height: 1.7),
    );
  }

  Widget _buildTagChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: page.tags
          .take(6)
          .map(
            (LinkAction tag) => LinkChip(
              label: tag.label,
              active: true,
              onTap: () => onTagTap(tag.label),
            ),
          )
          .toList(growable: false),
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

/// 标题按可用宽度自动降档。
///
/// 长标题在封面右侧那条窄列里会被压成一行三四个字，先逐级缩字号，
/// 实在放不下才在 [maxLines] 处截断。
class _AdaptiveTitle extends StatelessWidget {
  const _AdaptiveTitle({
    required this.text,
    required this.fontSizes,
    required this.lineHeight,
    this.color,
  });

  static const int maxLines = 3;

  /// 由大到小，第一个能塞进 [maxLines] 的就是最终字号。
  final List<double> fontSizes;
  final String text;
  final double lineHeight;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final String value = ChineseConverter.instance.convert(text);
    // 桌面主题会换字体，量算必须带上环境样式，否则算出来的行数是错的。
    final TextStyle baseStyle = DefaultTextStyle.of(context).style;
    final TextScaler textScaler = MediaQuery.textScalerOf(context);
    final TextDirection textDirection = Directionality.of(context);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        TextStyle styleOf(double fontSize) => baseStyle.merge(
          TextStyle(
            fontSize: fontSize,
            height: lineHeight,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        );

        TextStyle style = styleOf(fontSizes.last);
        for (final double fontSize in fontSizes) {
          final TextStyle candidate = styleOf(fontSize);
          if (_fits(
            candidate,
            value,
            constraints.maxWidth,
            textScaler,
            textDirection,
          )) {
            style = candidate;
            break;
          }
        }

        return Text(
          value,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
          style: style,
        );
      },
    );
  }

  bool _fits(
    TextStyle style,
    String value,
    double maxWidth,
    TextScaler textScaler,
    TextDirection textDirection,
  ) {
    if (!maxWidth.isFinite) {
      return true;
    }
    final TextPainter painter = TextPainter(
      text: TextSpan(text: value, style: style),
      maxLines: maxLines,
      textDirection: textDirection,
      textScaler: textScaler,
    )..layout(maxWidth: maxWidth);
    final bool fits = !painter.didExceedMaxLines;
    painter.dispose();
    return fits;
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

/// 章节分组切换的淡入容器：只让当前内容参与布局。
///
/// AnimatedSwitcher 默认的 layoutBuilder 会把旧内容一起塞进 Stack，切换章节
/// tab 时卡片高度被钉在旧列表上、旧章节压在新章节下面；同一话同时出现在两个
/// 分组里时，[ChapterGrid] 复用的 GlobalKey 还会撞车。旧内容直接退出即可。
class DetailSectionSwitcher extends StatelessWidget {
  const DetailSectionSwitcher({required this.contentKey, required this.child});

  final String contentKey;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) =>
          currentChild ?? const SizedBox.shrink(),
      transitionBuilder: (Widget child, Animation<double> animation) =>
          FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
            child: child,
          ),
      child: KeyedSubtree(key: ValueKey<String>(contentKey), child: child),
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
    // 格子铺在卡片里，填充必须比卡片高一档。暗色主题的 surfaceContainerLow 比卡片
    // 用的 surfaceContainerHigh 还暗，直接用会让格子变成挖在卡片上的黑洞。
    final Color tileColor = colorScheme.brightness == Brightness.light
        ? colorScheme.surfaceContainerLowest
        : colorScheme.surfaceContainerHighest;
    // 已缓存的底色跟着对勾图标走 success 色，之前的 primaryContainer 和状态本身没关系。
    final Color downloadedTileColor = Color.alphaBlend(
      downloadedColor.withValues(alpha: 0.12),
      tileColor,
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final bool isWideLayout = usesWideLayout(context);
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
            childAspectRatio: isWideLayout ? 2.6 : 2.0,
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
              borderRadius: BorderRadius.circular(14),
              child: Ink(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isLastRead
                      ? lastReadColor
                      : isDownloaded
                      ? downloadedTileColor
                      : tileColor,
                  borderRadius: BorderRadius.circular(14),
                  border: isLastRead
                      ? Border.all(color: lastReadBorderColor, width: 1.2)
                      : isDownloaded
                      ? Border.all(
                          color: downloadedColor.withValues(alpha: 0.72),
                        )
                      : Border.all(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.34,
                          ),
                        ),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        ChineseConverter.instance.convert(chapter.label),
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
