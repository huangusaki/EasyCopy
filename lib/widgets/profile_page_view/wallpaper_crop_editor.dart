part of '../profile_page_view.dart';

/// 壁纸裁剪选区编辑器，返回 0~1 的归一化 Rect。
class WallpaperCropEditorPage extends StatefulWidget {
  const WallpaperCropEditorPage({
    required this.imagePath,
    required this.initialCrop,
    super.key,
  });

  final String imagePath;
  final Rect initialCrop;

  @override
  State<WallpaperCropEditorPage> createState() =>
      _WallpaperCropEditorPageState();
}

enum _CropDragMode { none, move, topLeft, topRight, bottomLeft, bottomRight }

class _WallpaperCropEditorPageState extends State<WallpaperCropEditorPage> {
  static const double _handleHitRadius = 30;
  static const double _minExtent = WallpaperPreferences.minCropExtent;

  ui.Image? _image;
  bool _failed = false;
  ImageStream? _stream;
  ImageStreamListener? _streamListener;

  late double _left;
  late double _top;
  late double _width;
  late double _height;

  Rect _displayRect = Rect.zero;
  _CropDragMode _dragMode = _CropDragMode.none;
  Offset _lastPanPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    _left = widget.initialCrop.left.clamp(0.0, 1.0);
    _top = widget.initialCrop.top.clamp(0.0, 1.0);
    _width = widget.initialCrop.width.clamp(_minExtent, 1.0);
    _height = widget.initialCrop.height.clamp(_minExtent, 1.0);
    _left = _left.clamp(0.0, 1.0 - _width);
    _top = _top.clamp(0.0, 1.0 - _height);
    _resolveImage();
  }

  @override
  void dispose() {
    final ImageStreamListener? listener = _streamListener;
    if (listener != null) {
      _stream?.removeListener(listener);
    }
    _stream = null;
    _streamListener = null;
    super.dispose();
  }

  void _resolveImage() {
    final ImageStream stream = FileImage(
      File(widget.imagePath),
    ).resolve(ImageConfiguration.empty);
    final ImageStreamListener listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        if (!mounted) {
          return;
        }
        setState(() => _image = info.image);
      },
      onError: (Object error, StackTrace? stackTrace) {
        if (!mounted) {
          return;
        }
        setState(() => _failed = true);
      },
    );
    _stream = stream;
    _streamListener = listener;
    stream.addListener(listener);
  }

  Rect _computeDisplayRect(Size stage, ui.Image image) {
    final double imageAspect = image.width / image.height;
    final double stageAspect = stage.width / stage.height;
    double w;
    double h;
    if (imageAspect > stageAspect) {
      w = stage.width;
      h = w / imageAspect;
    } else {
      h = stage.height;
      w = h * imageAspect;
    }
    final double dx = (stage.width - w) / 2;
    final double dy = (stage.height - h) / 2;
    return Rect.fromLTWH(dx, dy, w, h);
  }

  Rect get _selectionPx {
    return Rect.fromLTWH(
      _displayRect.left + _left * _displayRect.width,
      _displayRect.top + _top * _displayRect.height,
      _width * _displayRect.width,
      _height * _displayRect.height,
    );
  }

  void _onPanStart(DragStartDetails details) {
    if (_displayRect.isEmpty) {
      return;
    }
    final Offset position = details.localPosition;
    final Rect selection = _selectionPx;
    _dragMode = _resolveDragMode(position, selection);
    _lastPanPosition = position;
  }

  _CropDragMode _resolveDragMode(Offset position, Rect selection) {
    bool near(Offset corner) =>
        (position - corner).distance <= _handleHitRadius;
    if (near(selection.topLeft)) {
      return _CropDragMode.topLeft;
    }
    if (near(selection.topRight)) {
      return _CropDragMode.topRight;
    }
    if (near(selection.bottomLeft)) {
      return _CropDragMode.bottomLeft;
    }
    if (near(selection.bottomRight)) {
      return _CropDragMode.bottomRight;
    }
    if (selection.contains(position)) {
      return _CropDragMode.move;
    }
    return _CropDragMode.none;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_dragMode == _CropDragMode.none || _displayRect.isEmpty) {
      return;
    }
    final Offset position = details.localPosition;
    if (_dragMode == _CropDragMode.move) {
      final Offset delta = position - _lastPanPosition;
      _lastPanPosition = position;
      setState(() {
        _left = (_left + delta.dx / _displayRect.width).clamp(
          0.0,
          1.0 - _width,
        );
        _top = (_top + delta.dy / _displayRect.height).clamp(
          0.0,
          1.0 - _height,
        );
      });
      return;
    }
    // 拖动角点，固定对角。
    final double nx = ((position.dx - _displayRect.left) / _displayRect.width)
        .clamp(0.0, 1.0);
    final double ny = ((position.dy - _displayRect.top) / _displayRect.height)
        .clamp(0.0, 1.0);
    final double right = _left + _width;
    final double bottom = _top + _height;
    setState(() {
      switch (_dragMode) {
        case _CropDragMode.topLeft:
          _left = nx.clamp(0.0, right - _minExtent);
          _top = ny.clamp(0.0, bottom - _minExtent);
          _width = right - _left;
          _height = bottom - _top;
          break;
        case _CropDragMode.topRight:
          final double newRight = nx.clamp(_left + _minExtent, 1.0);
          _top = ny.clamp(0.0, bottom - _minExtent);
          _width = newRight - _left;
          _height = bottom - _top;
          break;
        case _CropDragMode.bottomLeft:
          _left = nx.clamp(0.0, right - _minExtent);
          final double newBottom = ny.clamp(_top + _minExtent, 1.0);
          _width = right - _left;
          _height = newBottom - _top;
          break;
        case _CropDragMode.bottomRight:
          final double newRight = nx.clamp(_left + _minExtent, 1.0);
          final double newBottom = ny.clamp(_top + _minExtent, 1.0);
          _width = newRight - _left;
          _height = newBottom - _top;
          break;
        case _CropDragMode.move:
        case _CropDragMode.none:
          break;
      }
    });
  }

  void _onPanEnd(DragEndDetails details) {
    _dragMode = _CropDragMode.none;
  }

  void _resetCrop() {
    setState(() {
      _left = 0;
      _top = 0;
      _width = 1;
      _height = 1;
    });
  }

  void _confirm() {
    Navigator.of(
      context,
    ).pop(Rect.fromLTWH(_left, _top, _width, _height));
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final ui.Image? image = _image;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('调整壁纸选区'),
        actions: <Widget>[
          if (image != null)
            TextButton(
              onPressed: _resetCrop,
              child: const Text('重置', style: TextStyle(color: Colors.white)),
            ),
          if (image != null)
            TextButton(
              onPressed: _confirm,
              child: Text(
                '完成',
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
      body: _failed
          ? const Center(
              child: Text('无法加载图片', style: TextStyle(color: Colors.white70)),
            )
          : image == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: <Widget>[
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: LayoutBuilder(
                      builder:
                          (BuildContext context, BoxConstraints constraints) {
                            final Size stage = Size(
                              constraints.maxWidth,
                              constraints.maxHeight,
                            );
                            _displayRect = _computeDisplayRect(stage, image);
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanStart: _onPanStart,
                              onPanUpdate: _onPanUpdate,
                              onPanEnd: _onPanEnd,
                              child: Stack(
                                fit: StackFit.expand,
                                children: <Widget>[
                                  Positioned.fromRect(
                                    rect: _displayRect,
                                    child: RawImage(
                                      image: image,
                                      fit: BoxFit.fill,
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: _CropOverlayPainter(
                                        selection: _selectionPx,
                                        accent: colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Text(
                    '拖动选区移动位置，拖动四角调整大小。显示时该区域会以填充方式适配屏幕。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _CropOverlayPainter extends CustomPainter {
  _CropOverlayPainter({required this.selection, required this.accent});

  final Rect selection;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect full = Offset.zero & size;
    final Path scrim = Path.combine(
      PathOperation.difference,
      Path()..addRect(full),
      Path()..addRect(selection),
    );
    canvas.drawPath(scrim, Paint()..color = Colors.black.withValues(alpha: 0.55));

    canvas.drawRect(
      selection,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = accent,
    );

    final Paint gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = Colors.white.withValues(alpha: 0.5);
    for (int i = 1; i < 3; i += 1) {
      final double dx = selection.left + selection.width * i / 3;
      final double dy = selection.top + selection.height * i / 3;
      canvas.drawLine(
        Offset(dx, selection.top),
        Offset(dx, selection.bottom),
        gridPaint,
      );
      canvas.drawLine(
        Offset(selection.left, dy),
        Offset(selection.right, dy),
        gridPaint,
      );
    }

    final Paint handlePaint = Paint()..color = accent;
    const double r = 7;
    for (final Offset corner in <Offset>[
      selection.topLeft,
      selection.topRight,
      selection.bottomLeft,
      selection.bottomRight,
    ]) {
      canvas.drawCircle(corner, r, handlePaint);
    }
  }

  @override
  bool shouldRepaint(_CropOverlayPainter oldDelegate) {
    return oldDelegate.selection != selection || oldDelegate.accent != accent;
  }
}
