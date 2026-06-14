import 'package:flutter/material.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/widgets/cover_image.dart';
import 'package:reader/widgets/motion.dart';
import 'package:reader/widgets/responsive_layout.dart';

const double _comicCoverAspectRatio = 0.72;
const double _comicTilePadding = 6;
const double _comicTitleHeight = 33.6;
const double _comicCoverToTitleGap = 8;
const double _comicSubtitleGap = 4;
const double _comicSubtitleHeight = 14;
const double _comicSecondaryGap = 3;
const double _comicSecondaryHeight = 12;
const double _desktopComicTitleHeight = 38;
const double _desktopComicSubtitleHeight = 15;
const double _desktopComicSecondaryHeight = 14;
const double _comicMetaLineHeight = 1.2;
const double _comicLayoutSlack = 4;

double comicCardHeightFor({
  required double itemWidth,
  required bool hasSubtitle,
  required bool hasSecondary,
  bool isDesktop = false,
}) {
  double extra = 0;
  final double titleHeight = isDesktop
      ? _desktopComicTitleHeight
      : _comicTitleHeight;
  final double subtitleHeight = isDesktop
      ? _desktopComicSubtitleHeight
      : _comicSubtitleHeight;
  final double secondaryHeight = isDesktop
      ? _desktopComicSecondaryHeight
      : _comicSecondaryHeight;
  final double coverWidth = (itemWidth - _comicTilePadding * 2)
      .clamp(0.0, itemWidth)
      .toDouble();

  if (hasSubtitle) {
    extra += _comicSubtitleGap + subtitleHeight;
  }
  if (hasSecondary) {
    extra += _comicSecondaryGap + secondaryHeight;
  }
  return coverWidth / _comicCoverAspectRatio +
      _comicTilePadding * 2 +
      _comicCoverToTitleGap +
      titleHeight +
      extra +
      _comicLayoutSlack;
}

({bool hasSubtitle, bool hasSecondary}) comicMetaCoverage(
  List<ComicCardData> items,
) {
  bool hasSubtitle = false;
  bool hasSecondary = false;
  for (final ComicCardData item in items) {
    if (!hasSubtitle && item.subtitle.isNotEmpty) hasSubtitle = true;
    if (!hasSecondary && item.secondaryText.isNotEmpty) hasSecondary = true;
    if (hasSubtitle && hasSecondary) break;
  }
  return (hasSubtitle: hasSubtitle, hasSecondary: hasSecondary);
}

class ComicGrid extends StatelessWidget {
  const ComicGrid({
    required this.items,
    required this.onTap,
    this.onLongPress,
    this.emptyMessage = '暂时没有可展示的内容。',
    super.key,
  });

  final List<ComicCardData> items;
  final ValueChanged<String> onTap;
  final ValueChanged<String>? onLongPress;
  final String emptyMessage;

  static const int _crossAxisCount = 3;
  static const double _crossAxisSpacing = 12;
  static const double _mainAxisSpacing = 10;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Text(emptyMessage);
    }

    final ({bool hasSubtitle, bool hasSecondary}) meta = comicMetaCoverage(
      items,
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final int crossAxisCount = responsiveComicCrossAxisCount(
          context,
          maxWidth,
          spacing: _crossAxisSpacing,
          mobileCount: _crossAxisCount,
        );
        final double spacingWidth = _crossAxisSpacing * (crossAxisCount - 1);
        final double itemWidth = ((maxWidth - spacingWidth) / crossAxisCount)
            .clamp(0.0, maxWidth)
            .toDouble();

        if (itemWidth <= 0) {
          return const SizedBox.shrink();
        }

        final double itemHeight = comicCardHeightFor(
          itemWidth: itemWidth,
          hasSubtitle: meta.hasSubtitle,
          hasSecondary: meta.hasSecondary,
          isDesktop: usesDesktopLayout(context),
        );
        final int rowCount =
            (items.length + crossAxisCount - 1) ~/ crossAxisCount;
        final bool stagger = usesDesktopLayout(context);

        return Column(
          children: <Widget>[
            for (int rowIndex = 0; rowIndex < rowCount; rowIndex++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: rowIndex == rowCount - 1 ? 0 : _mainAxisSpacing,
                ),
                child: Row(
                  children: <Widget>[
                    for (
                      int columnIndex = 0;
                      columnIndex < crossAxisCount;
                      columnIndex++
                    ) ...<Widget>[
                      if (columnIndex > 0)
                        const SizedBox(width: _crossAxisSpacing),
                      SizedBox(
                        width: itemWidth,
                        height: itemHeight,
                        child: _buildItem(
                          rowIndex,
                          columnIndex,
                          crossAxisCount,
                          stagger: stagger,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildItem(
    int rowIndex,
    int columnIndex,
    int crossAxisCount, {
    required bool stagger,
  }) {
    final int itemIndex = rowIndex * crossAxisCount + columnIndex;
    if (itemIndex >= items.length) {
      return const SizedBox.shrink();
    }

    final ComicCardData item = items[itemIndex];
    return StaggerIn(
      key: ValueKey<String>(item.href),
      index: itemIndex,
      enabled: stagger,
      child: ComicCardTile(item: item, onTap: onTap, onLongPress: onLongPress),
    );
  }
}

class ComicSliverGrid extends StatelessWidget {
  const ComicSliverGrid({
    required this.items,
    required this.onTap,
    this.onLongPress,
    this.emptyMessage = '暂时没有可展示的内容。',
    super.key,
  });

  final List<ComicCardData> items;
  final ValueChanged<String> onTap;
  final ValueChanged<String>? onLongPress;
  final String emptyMessage;

  static const double _crossAxisSpacing = 12;
  static const double _mainAxisSpacing = 10;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return SliverToBoxAdapter(child: Text(emptyMessage));
    }

    final ({bool hasSubtitle, bool hasSecondary}) meta = comicMetaCoverage(
      items,
    );

    return SliverLayoutBuilder(
      builder: (BuildContext context, constraints) {
        final double availableWidth = constraints.crossAxisExtent;
        final int crossAxisCount = responsiveComicCrossAxisCount(
          context,
          availableWidth,
          spacing: _crossAxisSpacing,
        );
        final double spacingWidth = _crossAxisSpacing * (crossAxisCount - 1);
        final double itemWidth =
            ((availableWidth - spacingWidth) / crossAxisCount)
                .clamp(0.0, availableWidth)
                .toDouble();

        if (itemWidth <= 0) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }

        final double itemHeight = comicCardHeightFor(
          itemWidth: itemWidth,
          hasSubtitle: meta.hasSubtitle,
          hasSecondary: meta.hasSecondary,
          isDesktop: usesDesktopLayout(context),
        );
        final double aspectRatio = itemHeight <= 0
            ? 0.50
            : itemWidth / itemHeight;
        final bool stagger = usesDesktopLayout(context);

        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: _crossAxisSpacing,
            mainAxisSpacing: _mainAxisSpacing,
            childAspectRatio: aspectRatio,
          ),
          delegate: SliverChildBuilderDelegate(
            (BuildContext context, int index) {
              final ComicCardData item = items[index];
              return RepaintBoundary(
                child: StaggerIn(
                  key: ValueKey<String>(item.href),
                  index: index % (crossAxisCount * 2),
                  enabled: stagger,
                  child: ComicCardTile(
                    item: item,
                    onTap: onTap,
                    onLongPress: onLongPress,
                  ),
                ),
              );
            },
            childCount: items.length,
            addAutomaticKeepAlives: false,
          ),
        );
      },
    );
  }
}

class ComicCardTile extends StatefulWidget {
  const ComicCardTile({
    required this.item,
    required this.onTap,
    this.onLongPress,
    super.key,
  });

  final ComicCardData item;
  final ValueChanged<String> onTap;
  final ValueChanged<String>? onLongPress;

  @override
  State<ComicCardTile> createState() => _ComicCardTileState();
}

class _ComicCardTileState extends State<ComicCardTile> {
  bool _isHovered = false;

  void _handleTap() {
    widget.onTap(widget.item.href);
  }

  void _handleLongPress() {
    widget.onLongPress?.call(widget.item.href);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool isDesktop = usesDesktopLayout(context);

    final Widget cardContent = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AspectRatio(
          aspectRatio: _comicCoverAspectRatio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: AnimatedScale(
                    scale: _isHovered ? 1.05 : 1.0,
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    child: CoverImage(
                      imageUrl: widget.item.coverUrl,
                      aspectRatio: _comicCoverAspectRatio,
                    ),
                  ),
                ),
                if (widget.item.badge.isNotEmpty)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.secondary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        widget.item.badge,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: _comicCoverToTitleGap),
        SizedBox(
          height: isDesktop ? _desktopComicTitleHeight : _comicTitleHeight,
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            style: TextStyle(
              fontSize: isDesktop ? 15.5 : 14.0,
              height: _comicMetaLineHeight,
              fontWeight: FontWeight.w800,
              color: _isHovered ? colorScheme.primary : colorScheme.onSurface,
            ),
            child: Text(
              widget.item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (widget.item.subtitle.isNotEmpty) ...<Widget>[
          const SizedBox(height: _comicSubtitleGap),
          Text(
            widget.item.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.72),
              fontSize: isDesktop ? 12.0 : 11.0,
              height: _comicMetaLineHeight,
            ),
          ),
        ],
        if (widget.item.secondaryText.isNotEmpty) ...<Widget>[
          const SizedBox(height: _comicSecondaryGap),
          Text(
            widget.item.secondaryText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.56),
              fontSize: isDesktop ? 11.0 : 10.0,
              height: _comicMetaLineHeight,
            ),
          ),
        ],
      ],
    );

    final Widget cardContainer = AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      transform: _isHovered
          ? Matrix4.translationValues(0.0, -6.0, 0.0)
          : Matrix4.identity(),
      padding: const EdgeInsets.all(_comicTilePadding),
      decoration: BoxDecoration(
        color: _isHovered
            ? colorScheme.surfaceContainer.withValues(alpha: 0.75)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        boxShadow: <BoxShadow>[
          if (_isHovered)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: InkWell(
        onTap: _handleTap,
        onLongPress: widget.onLongPress == null ? null : _handleLongPress,
        borderRadius: BorderRadius.circular(20),
        child: cardContent,
      ),
    );

    if (isDesktop) {
      return MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: cardContainer,
      );
    }
    return cardContainer;
  }
}
