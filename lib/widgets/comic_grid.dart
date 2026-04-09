import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/widgets/cover_image.dart';
import 'package:flutter/material.dart';

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

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Text(emptyMessage);
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 14,
        childAspectRatio: 0.50,
      ),
      itemBuilder: (BuildContext context, int index) {
        final ComicCardData item = items[index];
        return _ComicCard(
          item: item,
          onTap: () => onTap(item.href),
          onLongPress: onLongPress == null
              ? null
              : () => onLongPress!(item.href),
        );
      },
    );
  }
}

class _ComicCard extends StatelessWidget {
  const _ComicCard({required this.item, required this.onTap, this.onLongPress});

  static const double _titleHeight = 33.6;

  final ComicCardData item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(20),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double coverHeight = constraints.maxHeight * 0.64;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                height: coverHeight,
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: EasyCopyCoverImage(
                        imageUrl: item.coverUrl,
                        aspectRatio: 0.72,
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
              const SizedBox(height: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      height: _titleHeight,
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
                      const SizedBox(height: 4),
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
                      const SizedBox(height: 3),
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
              ),
            ],
          );
        },
      ),
    );
  }
}
