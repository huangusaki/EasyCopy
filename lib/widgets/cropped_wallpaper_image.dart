import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 按归一化选区裁剪壁纸并 cover 填充。
///
/// 选区相对原图，取值 0~1。
class CroppedWallpaperImage extends StatefulWidget {
  const CroppedWallpaperImage({
    required this.path,
    required this.cropLeft,
    required this.cropTop,
    required this.cropWidth,
    required this.cropHeight,
    this.blurSigma = 0,
    this.fallback,
    super.key,
  });

  final String path;
  final double cropLeft;
  final double cropTop;
  final double cropWidth;
  final double cropHeight;
  final double blurSigma;
  final Widget? fallback;

  @override
  State<CroppedWallpaperImage> createState() => _CroppedWallpaperImageState();
}

class _CroppedWallpaperImageState extends State<CroppedWallpaperImage> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ui.Image? _image;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant CroppedWallpaperImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _resolveImage();
    }
  }

  @override
  void dispose() {
    _detachStream();
    super.dispose();
  }

  void _detachStream() {
    final ImageStreamListener? listener = _listener;
    if (listener != null) {
      _stream?.removeListener(listener);
    }
    _stream = null;
    _listener = null;
  }

  void _resolveImage() {
    _detachStream();
    setState(() {
      _image = null;
      _failed = false;
    });
    final ImageStream stream = FileImage(
      File(widget.path),
    ).resolve(ImageConfiguration.empty);
    final ImageStreamListener listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        if (!mounted) {
          return;
        }
        setState(() {
          _image = info.image;
          _failed = false;
        });
      },
      onError: (Object error, StackTrace? stackTrace) {
        if (!mounted) {
          return;
        }
        setState(() => _failed = true);
      },
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  @override
  Widget build(BuildContext context) {
    final ui.Image? image = _image;
    if (_failed || image == null) {
      return widget.fallback ?? const SizedBox.shrink();
    }
    Widget painted = ClipRect(
      child: CustomPaint(
        size: Size.infinite,
        painter: _CropPainter(
          image: image,
          cropLeft: widget.cropLeft,
          cropTop: widget.cropTop,
          cropWidth: widget.cropWidth,
          cropHeight: widget.cropHeight,
        ),
      ),
    );
    if (widget.blurSigma > 0.01) {
      painted = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(
          sigmaX: widget.blurSigma,
          sigmaY: widget.blurSigma,
        ),
        child: painted,
      );
    }
    return painted;
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter({
    required this.image,
    required this.cropLeft,
    required this.cropTop,
    required this.cropWidth,
    required this.cropHeight,
  });

  final ui.Image image;
  final double cropLeft;
  final double cropTop;
  final double cropWidth;
  final double cropHeight;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final double iw = image.width.toDouble();
    final double ih = image.height.toDouble();
    if (iw <= 0 || ih <= 0) {
      return;
    }
    Rect selection = Rect.fromLTWH(
      cropLeft * iw,
      cropTop * ih,
      cropWidth * iw,
      cropHeight * ih,
    ).intersect(Rect.fromLTWH(0, 0, iw, ih));
    if (selection.width <= 0 || selection.height <= 0) {
      selection = Rect.fromLTWH(0, 0, iw, ih);
    }

    final double destAspect = size.width / size.height;
    final double selAspect = selection.width / selection.height;
    final Rect src;
    if (selAspect > destAspect) {
      final double newWidth = selection.height * destAspect;
      src = Rect.fromLTWH(
        selection.left + (selection.width - newWidth) / 2,
        selection.top,
        newWidth,
        selection.height,
      );
    } else {
      final double newHeight = selection.width / destAspect;
      src = Rect.fromLTWH(
        selection.left,
        selection.top + (selection.height - newHeight) / 2,
        selection.width,
        newHeight,
      );
    }

    canvas.drawImageRect(
      image,
      src,
      Offset.zero & size,
      Paint()
        ..filterQuality = FilterQuality.high
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_CropPainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.cropLeft != cropLeft ||
        oldDelegate.cropTop != cropTop ||
        oldDelegate.cropWidth != cropWidth ||
        oldDelegate.cropHeight != cropHeight;
  }
}
