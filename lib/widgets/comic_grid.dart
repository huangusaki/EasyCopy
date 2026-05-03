import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/widgets/cover_image.dart';
import 'package:flutter/material.dart';

const double _comicCoverAspectRatio = 0.72;
const double _comicTitleHeight = 33.6;
const double _comicCoverToTitleGap = 8;
const double _comicSubtitleGap = 4;
const double _comicSubtitleHeight = 14;
const double _comicSecondaryGap = 3;
const double _comicSecondaryHeight = 12;

double comicCardHeightFor({
  required double itemWidth,
  required bool hasSubtitle,
  required bool hasSecondary,
}) {
  double extra = 0;
  if (hasSubtitle) {
    extra += _comicSubtitleGap + _comicSubtitleHeight;
  }
  if (hasSecondary) {
    extra += _comicSecondaryGap + _comicSecondaryHeight;
  }
  return itemWidth / _comicCoverAspectRatio +
      _comicCoverToTitleGap +
      _comicTitleHeight +
      extra;
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
    this.emptyMessage = '暫時沒有可展示的內容。',
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
        final double spacingWidth = _crossAxisSpacing * (_crossAxisCount - 1);
        final double itemWidth = ((maxWidth - spacingWidth) / _crossAxisCount)
            .clamp(0.0, maxWidth)
            .toDouble();

        if (itemWidth <= 0) {
          return const SizedBox.shrink();
        }

        final double itemHeight = comicCardHeightFor(
          itemWidth: itemWidth,
          hasSubtitle: meta.hasSubtitle,
          hasSecondary: meta.hasSecondary,
        );
        final int rowCount =
            (items.length + _crossAxisCount - 1) ~/ _crossAxisCount;

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
                      columnIndex < _crossAxisCount;
                      columnIndex++
                    ) ...<Widget>[
                      if (columnIndex > 0)
                        const SizedBox(width: _crossAxisSpacing),
                      SizedBox(
                        width: itemWidth,
                        height: itemHeight,
                        child: _buildItem(rowIndex, columnIndex),
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

  Widget _buildItem(int rowIndex, int columnIndex) {
    final int itemIndex = rowIndex * _crossAxisCount + columnIndex;
    if (itemIndex >= items.length) {
      return const SizedBox.shrink();
    }

    final ComicCardData item = items[itemIndex];
    return ComicCardTile(
      key: ValueKey<String>(item.href),
      item: item,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}

class ComicCardTile extends StatelessWidget {
  const ComicCardTile({
    required this.item,
    required this.onTap,
    this.onLongPress,
    super.key,
  });

  final ComicCardData item;
  final ValueChanged<String> onTap;
  final ValueChanged<String>? onLongPress;

  void _handleTap() {
    onTap(item.href);
  }

  void _handleLongPress() {
    onLongPress?.call(item.href);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: _handleTap,
      onLongPress: onLongPress == null ? null : _handleLongPress,
      borderRadius: BorderRadius.circular(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AspectRatio(
            aspectRatio: _comicCoverAspectRatio,
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: EasyCopyCoverImage(
                    imageUrl: item.coverUrl,
                    aspectRatio: _comicCoverAspectRatio,
                  ),
                ),
                if (item.badge.isNotEmpty)
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
                        item.badge,
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
          const SizedBox(height: _comicCoverToTitleGap),
          SizedBox(
            height: _comicTitleHeight,
            child: Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                height: 1.2,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (item.subtitle.isNotEmpty) ...<Widget>[
            const SizedBox(height: _comicSubtitleGap),
            Text(
              item.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.72),
                fontSize: 11,
              ),
            ),
          ],
          if (item.secondaryText.isNotEmpty) ...<Widget>[
            const SizedBox(height: _comicSecondaryGap),
            Text(
              item.secondaryText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.56),
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
