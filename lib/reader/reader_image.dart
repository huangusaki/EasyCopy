import 'package:flutter/material.dart';
import 'package:reader/services/debug_trace.dart';

class ReaderChapterImage extends StatefulWidget {
  const ReaderChapterImage({
    super.key,
    required this.imageProvider,
    required this.debugUrl,
    required this.fit,
    required this.onResolvedAspectRatio,
    this.viewportHeight,
    this.aspectRatio,
    this.alignment = Alignment.center,
  });

  final ImageProvider<Object> imageProvider;
  final String debugUrl;
  final BoxFit fit;
  final ValueChanged<double> onResolvedAspectRatio;
  final double? viewportHeight;
  final double? aspectRatio;
  final Alignment alignment;

  @override
  State<ReaderChapterImage> createState() => _ReaderChapterImageState();
}

class _ReaderChapterImageState extends State<ReaderChapterImage> {
  ImageStream? _imageStream;
  ImageStreamListener? _imageStreamListener;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant ReaderChapterImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageProvider != widget.imageProvider) {
      _resolveImage();
    }
  }

  @override
  void dispose() {
    _detachImageStream();
    super.dispose();
  }

  void _resolveImage() {
    final ImageStream newStream = widget.imageProvider.resolve(
      createLocalImageConfiguration(context),
    );
    if (_imageStream?.key == newStream.key) {
      return;
    }
    _detachImageStream();
    _imageStream = newStream;
    _imageStreamListener = ImageStreamListener(
      (ImageInfo imageInfo, bool synchronousCall) {
        final int width = imageInfo.image.width;
        final int height = imageInfo.image.height;
        imageInfo.dispose();
        if (!mounted || width <= 0 || height <= 0) return;
        final ValueChanged<double> onResolved = widget.onResolvedAspectRatio;
        if (synchronousCall) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) onResolved(width / height);
          });
        } else {
          onResolved(width / height);
        }
      },
      onError: (Object error, StackTrace? stackTrace) {
        if (!mounted) {
          return;
        }
        DebugTrace.log('reader.image_error', <String, Object?>{
          'url': widget.debugUrl,
          'error': error.toString(),
        });
      },
    );
    _imageStream!.addListener(_imageStreamListener!);
  }

  void _detachImageStream() {
    final ImageStream? imageStream = _imageStream;
    final ImageStreamListener? imageStreamListener = _imageStreamListener;
    if (imageStream != null && imageStreamListener != null) {
      imageStream.removeListener(imageStreamListener);
    }
    _imageStream = null;
    _imageStreamListener = null;
  }

  Widget _buildLoadingBox() {
    return Center(
      child: CircularProgressIndicator(
        strokeWidth: widget.viewportHeight == null ? 2.4 : 3,
      ),
    );
  }

  Widget _buildErrorBox() {
    return const Center(child: Icon(Icons.broken_image_outlined, size: 36));
  }

  @override
  Widget build(BuildContext context) {
    final double resolvedAspectRatio = widget.aspectRatio ?? 0.72;
    final Widget image = Image(
      image: widget.imageProvider,
      fit: widget.fit,
      alignment: widget.alignment,
      width: double.infinity,
      height: widget.viewportHeight,
      gaplessPlayback: true,
      errorBuilder:
          (BuildContext context, Object error, StackTrace? stackTrace) {
            return SizedBox(
              height: widget.viewportHeight,
              child: _buildErrorBox(),
            );
          },
      frameBuilder:
          (
            BuildContext context,
            Widget child,
            int? frame,
            bool wasSynchronouslyLoaded,
          ) {
            final bool isLoaded = wasSynchronouslyLoaded || frame != null;
            if (widget.viewportHeight != null) {
              return SizedBox(
                height: widget.viewportHeight,
                child: isLoaded ? child : _buildLoadingBox(),
              );
            }
            return AspectRatio(
              aspectRatio: resolvedAspectRatio,
              child: isLoaded ? child : _buildLoadingBox(),
            );
          },
    );
    if (widget.viewportHeight != null) {
      return image;
    }
    return RepaintBoundary(child: image);
  }
}
