import 'package:easy_copy/services/debug_trace.dart';
import 'package:flutter/material.dart';

class ReaderChapterImage extends StatefulWidget {
  const ReaderChapterImage({
    super.key,
    required this.imageProvider,
    required this.debugUrl,
    required this.fit,
    required this.onResolvedAspectRatio,
    this.viewportHeight,
    this.aspectRatio,
  });

  final ImageProvider<Object> imageProvider;
  final String debugUrl;
  final BoxFit fit;
  final ValueChanged<double> onResolvedAspectRatio;
  final double? viewportHeight;
  final double? aspectRatio;

  @override
  State<ReaderChapterImage> createState() => _ReaderChapterImageState();
}

class _ReaderChapterImageState extends State<ReaderChapterImage> {
  ImageStream? _imageStream;
  ImageStreamListener? _imageStreamListener;
  bool _hasFrame = false;
  bool _hasError = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant ReaderChapterImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageProvider != widget.imageProvider) {
      _hasFrame = false;
      _hasError = false;
      _resolveImage(force: true);
      return;
    }
    if (oldWidget.aspectRatio != widget.aspectRatio &&
        widget.aspectRatio != null &&
        !_hasFrame) {
      setState(() {
        _hasFrame = true;
      });
    }
  }

  @override
  void dispose() {
    _detachImageStream();
    super.dispose();
  }

  void _resolveImage({bool force = false}) {
    final ImageStream newStream = widget.imageProvider.resolve(
      createLocalImageConfiguration(context),
    );
    if (!force && _imageStream?.key == newStream.key) {
      return;
    }
    _detachImageStream();
    _imageStream = newStream;
    _imageStreamListener = ImageStreamListener(
      (ImageInfo imageInfo, bool synchronousCall) {
        final int width = imageInfo.image.width;
        final int height = imageInfo.image.height;
        if (width > 0 && height > 0) {
          widget.onResolvedAspectRatio(width / height);
        }
        if (!mounted || _hasFrame) {
          return;
        }
        setState(() {
          _hasFrame = true;
          _hasError = false;
        });
      },
      onError: (Object error, StackTrace? stackTrace) {
        if (!mounted) {
          return;
        }
        DebugTrace.log('reader.image_error', <String, Object?>{
          'url': widget.debugUrl,
          'error': error.toString(),
        });
        setState(() {
          _hasError = true;
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
            final bool isLoaded =
                wasSynchronouslyLoaded || frame != null || _hasFrame;
            if (widget.viewportHeight != null) {
              return SizedBox(
                height: widget.viewportHeight,
                child: isLoaded ? child : _buildLoadingBox(),
              );
            }
            return AspectRatio(
              aspectRatio: resolvedAspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Positioned.fill(
                    child: isLoaded
                        ? child
                        : (_hasError ? _buildErrorBox() : _buildLoadingBox()),
                  ),
                ],
              ),
            );
          },
    );
    if (widget.viewportHeight != null) {
      return image;
    }
    return RepaintBoundary(child: image);
  }
}
