import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_copy/services/image_cache.dart';
import 'package:flutter/material.dart';

class EasyCopyCoverImage extends StatelessWidget {
  const EasyCopyCoverImage({
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
    Widget child = imageUrl.isEmpty
        ? const EasyCopyPlaceholderImage()
        : CachedNetworkImage(
            imageUrl: imageUrl,
            fit: fit,
            cacheManager: EasyCopyImageCaches.coverCache,
            errorWidget: (_, __, ___) => const EasyCopyPlaceholderImage(),
          );

    if (aspectRatio != null) {
      child = AspectRatio(aspectRatio: aspectRatio!, child: child);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: child,
    );
  }
}

class EasyCopyPlaceholderImage extends StatelessWidget {
  const EasyCopyPlaceholderImage({super.key});

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
