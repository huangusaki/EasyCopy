import 'package:flutter/material.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/services/chinese_converter.dart';
import 'package:reader/widgets/cover_image.dart';
import 'package:reader/widgets/motion.dart';
import 'package:reader/widgets/responsive_layout.dart';

const double _comicCoverAspectRatio = 0.72;
const double _comicTilePadding = ComicCardInk.contentPadding;
const double _comicTitleFontSize = 14;
const double _comicCoverToTitleGap = 8;
const double _comicSubtitleGap = 4;
const double _comicSubtitleFontSize = 11;
const double _comicSecondaryGap = 3;
const double _comicSecondaryFontSize = 10;
const double _wideComicTitleFontSize = 15.5;
const double _wideComicSubtitleFontSize = 12;
const double _wideComicSecondaryFontSize = 11;
const double _comicMetaLineHeight = 1.2;
const double _comicLayoutSlack = 4;

/// 先缩放字号再乘行高与行数：安卓 14+ 的非线性字体缩放对大数值放大得更少，
/// 直接 scale(总高度) 会比实际文字矮，第二行被裁掉。
double scaledTextBlockHeight(
  TextScaler textScaler,
  double fontSize, {
  int lines = 1,
  double lineHeight = _comicMetaLineHeight,
}) {
  return textScaler.scale(fontSize) * lineHeight * lines;
}

double comicCardTitleHeightFor({
  required bool isWideLayout,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return scaledTextBlockHeight(
    textScaler,
    isWideLayout ? _wideComicTitleFontSize : _comicTitleFontSize,
    lines: 2,
  );
}

double comicCardHeightFor({
  required double itemWidth,
  required bool hasSubtitle,
  required bool hasSecondary,
  bool isWideLayout = false,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  double extra = 0;
  final double titleHeight = comicCardTitleHeightFor(
    isWideLayout: isWideLayout,
    textScaler: textScaler,
  );
  final double subtitleHeight = scaledTextBlockHeight(
    textScaler,
    isWideLayout ? _wideComicSubtitleFontSize : _comicSubtitleFontSize,
  );
  final double secondaryHeight = scaledTextBlockHeight(
    textScaler,
    isWideLayout ? _wideComicSecondaryFontSize : _comicSecondaryFontSize,
  );
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
  Iterable<ComicCardData> items,
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

class ComicSliverGrid extends StatelessWidget {
  const ComicSliverGrid({
    required this.items,
    required this.onTap,
    this.onLongPress,
    this.metadata,
    this.animateItems = true,
    this.emptyMessage = '暂时没有可展示的内容。',
    super.key,
  });

  final Iterable<ComicCardData> items;
  final ({bool hasSubtitle, bool hasSecondary})? metadata;
  final ValueChanged<String> onTap;
  final ValueChanged<ComicCardData>? onLongPress;
  final bool animateItems;
  final String emptyMessage;

  static const double _crossAxisSpacing = 12;
  static const double _mainAxisSpacing = 10;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return SliverToBoxAdapter(child: Text(emptyMessage));
    }

    final ({bool hasSubtitle, bool hasSecondary}) meta =
        metadata ?? comicMetaCoverage(items);

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
          isWideLayout: usesWideLayout(context),
          textScaler: MediaQuery.textScalerOf(context),
        );
        final double aspectRatio = itemHeight <= 0
            ? 0.50
            : itemWidth / itemHeight;
        final bool stagger = usesWideLayout(context);

        return SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: _crossAxisSpacing,
            mainAxisSpacing: _mainAxisSpacing,
            childAspectRatio: aspectRatio,
          ),
          delegate: SliverChildBuilderDelegate(
            (BuildContext context, int index) {
              final ComicCardData item = items.elementAt(index);
              final Widget tile = ComicCardTile(
                item: item,
                onTap: onTap,
                onLongPress: onLongPress == null
                    ? null
                    : (_) => onLongPress!(item),
              );
              return animateItems
                  ? StaggerIn(
                      key: ValueKey<String>(item.href),
                      index: index % (crossAxisCount * 2),
                      enabled: stagger,
                      child: tile,
                    )
                  : tile;
            },
            childCount: items.length,
            addAutomaticKeepAlives: false,
          ),
        );
      },
    );
  }
}

/// 按压反馈直接覆盖整张卡片，封面和文字共用同一块圆角遮罩。
class ComicCardInk extends StatefulWidget {
  static const double contentPadding = 6;

  const ComicCardInk({
    required this.child,
    required this.onTap,
    this.onLongPress,
    super.key,
  });

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  State<ComicCardInk> createState() => _ComicCardInkState();
}

class _ComicCardInkState extends State<ComicCardInk> {
  final WidgetStatesController _states = WidgetStatesController();

  @override
  void dispose() {
    _states.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color feedbackColor = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      statesController: _states,
      splashFactory: NoSplash.splashFactory,
      overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      child: ListenableBuilder(
        listenable: _states,
        child: Padding(
          padding: const EdgeInsets.all(ComicCardInk.contentPadding),
          child: widget.child,
        ),
        builder: (BuildContext context, Widget? child) {
          final Set<WidgetState> states = _states.value;
          final double opacity = states.contains(WidgetState.pressed)
              ? 0.10
              : states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.focused)
              ? 0.06
              : 0;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            foregroundDecoration: BoxDecoration(
              color: feedbackColor.withValues(alpha: opacity),
              borderRadius: BorderRadius.circular(20),
            ),
            child: child,
          );
        },
      ),
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
    final bool isWideLayout = usesWideLayout(context);

    final titleStyle = TextStyle(
      fontSize: isWideLayout ? _wideComicTitleFontSize : _comicTitleFontSize,
      height: _comicMetaLineHeight,
      fontWeight: FontWeight.w800,
      color: isWideLayout && _isHovered
          ? colorScheme.primary
          : colorScheme.onSurface,
    );
    final title = Text(
      ChineseConverter.instance.convert(widget.item.title),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: isWideLayout ? null : titleStyle,
    );
    final cover = CoverImage(
      imageUrl: widget.item.coverUrl,
      aspectRatio: _comicCoverAspectRatio,
      borderRadius: 0,
    );
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
                  child: !isWideLayout
                      ? cover
                      : AnimatedScale(
                          scale: _isHovered ? 1.05 : 1.0,
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                          child: cover,
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
                        ChineseConverter.instance.convert(widget.item.badge),
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
          height: comicCardTitleHeightFor(
            isWideLayout: isWideLayout,
            textScaler: MediaQuery.textScalerOf(context),
          ),
          child: isWideLayout
              ? AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  style: titleStyle,
                  child: title,
                )
              : title,
        ),
        if (widget.item.subtitle.isNotEmpty) ...<Widget>[
          const SizedBox(height: _comicSubtitleGap),
          Text(
            ChineseConverter.instance.convert(widget.item.subtitle),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.72),
              fontSize: isWideLayout
                  ? _wideComicSubtitleFontSize
                  : _comicSubtitleFontSize,
              height: _comicMetaLineHeight,
            ),
          ),
        ],
        if (widget.item.secondaryText.isNotEmpty) ...<Widget>[
          const SizedBox(height: _comicSecondaryGap),
          Text(
            ChineseConverter.instance.convert(widget.item.secondaryText),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.56),
              fontSize: isWideLayout
                  ? _wideComicSecondaryFontSize
                  : _comicSecondaryFontSize,
              height: _comicMetaLineHeight,
            ),
          ),
        ],
      ],
    );

    final ink = ComicCardInk(
      onTap: _handleTap,
      onLongPress: widget.onLongPress == null ? null : _handleLongPress,
      child: cardContent,
    );
    if (!isWideLayout) return ink;
    final Widget cardContainer = AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      transform: _isHovered
          ? Matrix4.translationValues(0.0, -6.0, 0.0)
          : Matrix4.identity(),
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
      child: ink,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: cardContainer,
    );
  }
}
