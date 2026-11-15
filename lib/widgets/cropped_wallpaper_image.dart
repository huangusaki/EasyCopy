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
  /// 壁纸只做全屏背景，解码上限足够覆盖平板分辨率与常见裁剪比例；
  /// 原图直接解码一张 12MP 照片就要常驻约 48MB。
  static const int _maxDecodeExtent = 2560;

  ImageStream? _stream;
  ImageStreamListener? _listener;
  ui.Image? _image;
  bool _failed = false;

  /// 模糊结果烘焙成位图：实时 ImageFiltered 在每次内容重绘（如滚动）时
  /// 都要整屏重新模糊。
  ui.Image? _blurred;
  Object? _blurredKey;

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
    _replaceBlurred(null, null);
    super.dispose();
  }

  void _replaceBlurred(ui.Image? image, Object? key) {
    _blurred?.dispose();
    _blurred = image;
    _blurredKey = key;
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
      _replaceBlurred(null, null);
    });
    final ImageStream stream = ResizeImage(
      FileImage(File(widget.path)),
      width: _maxDecodeExtent,
      height: _maxDecodeExtent,
      policy: ResizeImagePolicy.fit,
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
    final _CropPainter painter = _CropPainter(
      image: image,
      cropLeft: widget.cropLeft,
      cropTop: widget.cropTop,
      cropWidth: widget.cropWidth,
      cropHeight: widget.cropHeight,
    );
    if (widget.blurSigma <= 0.01) {
      return ClipRect(
        child: CustomPaint(size: Size.infinite, painter: painter),
      );
    }
    final double pixelRatio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = constraints.biggest;
        if (!size.isFinite || size.isEmpty) {
          return const SizedBox.shrink();
        }
        return RawImage(
          image: _bakeBlurred(painter, size, pixelRatio),
          width: size.width,
          height: size.height,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.low,
        );
      },
    );
  }

  ui.Image _bakeBlurred(_CropPainter painter, Size size, double pixelRatio) {
    final Object key = Object.hash(
      painter.image,
      painter.cropLeft,
      painter.cropTop,
      painter.cropWidth,
      painter.cropHeight,
      widget.blurSigma,
      size,
      pixelRatio,
    );
    final ui.Image? cached = _blurred;
    if (cached != null && _blurredKey == key) {
      return cached;
    }
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder)..scale(pixelRatio);
    final Rect bounds = Offset.zero & size;
    canvas
      ..clipRect(bounds)
      ..saveLayer(
        bounds,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: widget.blurSigma,
            sigmaY: widget.blurSigma,
          ),
      );
    painter.paint(canvas, size);
    canvas.restore();
    final ui.Picture picture = recorder.endRecording();
    final ui.Image baked = picture.toImageSync(
      (size.width * pixelRatio).ceil(),
      (size.height * pixelRatio).ceil(),
    );
    picture.dispose();
    _replaceBlurred(baked, key);
    return baked;
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
