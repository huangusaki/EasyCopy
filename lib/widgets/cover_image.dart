import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:reader/services/image_cache.dart';

class CoverImage extends StatelessWidget {
  const CoverImage({
    required this.imageUrl,
    this.aspectRatio,
    this.borderRadius = 20,
    this.fit = BoxFit.cover,
    super.key,
  });

  final String imageUrl;
  final double? aspectRatio;
  final double borderRadius;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        Widget child = imageUrl.isEmpty
            ? const PlaceholderImage()
            : CachedNetworkImage(
                imageUrl: imageUrl,
                fit: fit,
                memCacheWidth: _coverCacheWidth(context, constraints),
                cacheManager: AppImageCaches.coverCache,
                placeholder: (_, __) => const CoverSkeleton(),
                errorWidget: (_, __, ___) => const PlaceholderImage(),
              );

        if (aspectRatio != null) {
          child = AspectRatio(aspectRatio: aspectRatio!, child: child);
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: child,
        );
      },
    );
  }

  int? _coverCacheWidth(BuildContext context, BoxConstraints constraints) {
    final double logicalWidth = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : MediaQuery.sizeOf(context).width;
    if (!logicalWidth.isFinite || logicalWidth <= 0) {
      return null;
    }

    final double devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    return (logicalWidth * devicePixelRatio).ceil().clamp(160, 720).toInt();
  }
}

class PlaceholderImage extends StatelessWidget {
  const PlaceholderImage({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colorScheme.surfaceContainerHigh,
            colorScheme.surfaceContainerHighest,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: 28,
          color: colorScheme.onSurface.withValues(alpha: 0.42),
        ),
      ),
    );
  }
}

class CoverSkeleton extends StatelessWidget {
  const CoverSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: colorScheme.surfaceContainerHigh),
    );
  }
}
