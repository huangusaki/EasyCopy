import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:reader/reader/internal/reader_book_layout.dart';

final Future<ui.Image> _paper = () {
  final math.Random random = math.Random(7);
  final Uint8List pixels = Uint8List(64 * 64 * 4);
  for (int i = 0; i < pixels.length; i += 4) {
    if (random.nextInt(32) != 0) continue;
    pixels.fillRange(i, i + 4, 255);
  }
  final Completer<ui.Image> ready = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    64,
    64,
    ui.PixelFormat.rgba8888,
    ready.complete,
  );
  return ready.future;
}();

class ReaderBook extends StatefulWidget {
  const ReaderBook({
    required this.index,
    required this.pages,
    required this.reverse,
    required this.enabled,
    required this.animate,
    required this.pageBuilder,
    required this.onChanged,
    required this.onEdge,
    required this.onStart,
    required this.onEnd,
    super.key,
  });

  static const Color paper = Color(0xfffaf9f6);

  final int index;
  final List<BookSpread> pages;
  int get count => pages.length;
  final bool reverse;
  final bool enabled;
  final bool animate;
  final Widget Function(BuildContext context, int index, bool? right)
  pageBuilder;
  final ValueChanged<int> onChanged;
  final ValueChanged<bool> onEdge;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  @override
  State<ReaderBook> createState() => ReaderBookState();
}

class ReaderBookState extends State<ReaderBook>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(vsync: this);
  late int _index = widget.index;
  int? _to;
  Size _size = Size.zero;
  double _dx = 0;
  double _dy = 0;
  double _grip = 0;
  bool _dragging = false;
  ui.Image? _grain;
  // Pages keep their elements while moving between the idle spread and the
  // fold layers, so starting or landing a turn does not rebuild them.
  final Map<(int, int, bool, bool?), GlobalKey> _leaves =
      <(int, int, bool, bool?), GlobalKey>{};

  bool get _right => (_to! > _index) != widget.reverse;
  bool get _valid => _to != null && _to! >= 0 && _to! < widget.count;

  @override
  void initState() {
    super.initState();
    unawaited(
      _paper.then((ui.Image image) {
        if (mounted) setState(() => _grain = image);
      }),
    );
  }

  @override
  void didUpdateWidget(covariant ReaderBook oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index ||
        widget.pages != oldWidget.pages ||
        widget.reverse != oldWidget.reverse ||
        widget.animate != oldWidget.animate ||
        !widget.enabled) {
      // Fresh keys for outside jumps: the switcher may still hold old pages.
      if (widget.index != _index || widget.pages != oldWidget.pages) {
        _leaves.clear();
      }
      _reset();
      _index = widget.index;
    }
  }

  void _reset() {
    final bool active = _to != null || _dragging;
    _turn.stop();
    _to = null;
    _dragging = false;
    if (active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onEnd();
      });
    }
  }

  void cancelTurn() {
    setState(_reset);
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  Future<void> turnTo(int index) async {
    if (!widget.enabled || index == _index || _dragging || _turn.isAnimating) {
      return;
    }
    widget.onStart();
    setState(() {
      _to = index;
      _grip = _size.height * 0.8;
      _dy = 0;
      _turn.value = 0;
    });
    // Taps lift the leaf briskly rather than easing in from rest.
    await _settle(true, 3.6);
  }

  void _start(DragStartDetails details) {
    if (_turn.isAnimating) return;
    _dragging = true;
    _dx = 0;
    _dy = 0;
    _grip = details.localPosition.dy;
    _turn.value = 0;
    widget.onStart();
  }

  void _update(DragUpdateDetails details) {
    if (!_dragging || !widget.enabled) return;
    _dx += details.delta.dx;
    _dy += details.delta.dy;
    final bool forward = (_dx < 0) != widget.reverse;
    final int to = _index + (forward ? 1 : -1);
    if (_to != to) setState(() => _to = to);
    if (widget.animate && _valid) {
      _turn.value = (_dx.abs() / _size.width).clamp(0, 1);
    }
  }

  void _end(DragEndDetails details) {
    if (!_dragging) return;
    _dragging = false;
    final double speed = details.primaryVelocity ?? 0;
    final bool finish = speed.abs() >= 450
        ? speed.sign == _dx.sign
        : _dx.abs() >= _size.width * 0.24;
    unawaited(_settle(finish, _dx.sign * speed / _size.width));
  }

  void _cancel() {
    if (!_dragging) return;
    _dragging = false;
    unawaited(_settle(false));
  }

  /// [velocity] is in turn progress per second; the leaf leaves at that speed.
  Future<void> _settle(bool finish, [double velocity = 0]) async {
    final int? to = _to;
    if (to == null) {
      widget.onEnd();
      return;
    }
    final bool valid = _valid;
    if (widget.animate && valid) {
      final double end = finish ? 1 : 0;
      final double distance = (end - _turn.value).abs();
      final double toward = velocity * (end - _turn.value).sign;
      final double longest = 0.1 + 0.28 * distance;
      final double seconds = toward > 0
          ? (2 * distance / toward).clamp(math.min(0.1, longest), longest)
          : longest;
      try {
        await _turn
            .animateTo(
              end,
              duration: Duration(microseconds: (seconds * 1e6).round()),
              curve: _Release(
                distance == 0 ? 0 : (toward * seconds / distance).clamp(0, 3),
              ),
            )
            .orCancel;
      } on TickerCanceled {
        return;
      }
    }
    if (!mounted) return;
    final bool forward = to > _index;
    setState(() {
      if (finish && valid) _index = to;
      _to = null;
    });
    if (finish) {
      if (valid) {
        widget.onChanged(to);
      } else {
        widget.onEdge(forward);
      }
    }
    widget.onEnd();
  }

  Widget _page(int index, bool? right) {
    final BookSpread spread = widget.pages[index];
    return Positioned(
      left: right == true ? _size.width / 2 : 0,
      width: right == null ? _size.width : _size.width / 2,
      top: 0,
      height: _size.height,
      child: RepaintBoundary(
        key: _leaves.putIfAbsent((
          spread.start,
          spread.end,
          spread.wide,
          right,
        ), GlobalKey.new),
        child: CustomPaint(
          foregroundPainter: _grain == null
              ? null
              : _PaperGrain(_grain!, Colors.black.withValues(alpha: 0.025)),
          child: ColoredBox(
            color: ReaderBook.paper,
            child: Builder(
              builder: (BuildContext context) =>
                  widget.pageBuilder(context, index, right),
            ),
          ),
        ),
      ),
    );
  }

  Widget _spine() => Positioned(
    left: _size.width / 2 - 32,
    top: 0,
    bottom: 0,
    width: 64,
    child: const IgnorePointer(
      child: RepaintBoundary(child: CustomPaint(painter: _BookSpine())),
    ),
  );

  Widget _spread(int index) => Stack(
    key: ValueKey<(int, int, bool)>((
      widget.pages[index].start,
      widget.pages[index].end,
      widget.pages[index].wide,
    )),
    fit: StackFit.expand,
    children: <Widget>[
      if (widget.pages[index].wide)
        _page(index, null)
      else ...<Widget>[_page(index, false), _page(index, true), _spine()],
    ],
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final ThemeData theme = Theme.of(context);
        final ThemeData paperTheme = ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: theme.colorScheme.primary,
            surface: ReaderBook.paper,
          ),
          textTheme: theme.textTheme.apply(
            bodyColor: Colors.black87,
            displayColor: Colors.black87,
          ),
        );
        final Size size = applyBoxFit(
          BoxFit.contain,
          const Size(1.44, 1),
          constraints.biggest,
        ).destination;
        if (size != _size) {
          _reset();
          _size = size;
        }
        final bool moving = _valid && widget.animate;
        final Set<int> near = <int>{
          for (final int i in <int>[_index - 1, _index, _index + 1])
            if (i >= 0 && i < widget.count) widget.pages[i].start,
          if (_valid) widget.pages[_to!].start,
        };
        _leaves.removeWhere(
          ((int, int, bool, bool?) key, _) => !near.contains(key.$1),
        );
        final bool sliding =
            moving && (widget.pages[_index].wide || widget.pages[_to!].wide);
        final bool folding = moving && !sliding;
        final Widget current = _spread(_index);
        final Widget? next = sliding ? _spread(_to!) : null;
        final Widget front = Stack(
          children: <Widget>[if (folding) _page(_index, _right)],
        );
        final Widget back = Stack(
          children: <Widget>[if (folding) _page(_to!, !_right)],
        );
        final Widget base = Stack(
          children: <Widget>[
            _page(_index, folding ? !_right : false),
            _page(folding ? _to! : _index, folding ? _right : true),
          ],
        );
        final Widget spine = _spine();
        final Widget book = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: widget.enabled ? _start : null,
          onHorizontalDragUpdate: widget.enabled ? _update : null,
          onHorizontalDragEnd: widget.enabled ? _end : null,
          onHorizontalDragCancel: widget.enabled ? _cancel : null,
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _turn,
              builder: (BuildContext context, Widget? _) {
                if (sliding) {
                  final double t = _turn.value;
                  final double dx = (_right ? -1 : 1) * size.width;
                  final bool forward = _to! > _index;
                  // The upper spread slides over the lower one, which drifts
                  // with a little parallax and dims while it is covered.
                  return Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      Transform.translate(
                        offset: Offset(dx * (forward ? t : t - 1) * 0.3, 0),
                        child: forward ? current : next,
                      ),
                      IgnorePointer(
                        child: ColoredBox(
                          color: Colors.black.withValues(
                            alpha: 0.22 * (forward ? t : 1 - t),
                          ),
                        ),
                      ),
                      Transform.translate(
                        offset: Offset(dx * (forward ? t - 1 : t), 0),
                        child: DecoratedBox(
                          decoration: const BoxDecoration(
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: Color(0x47000000),
                                blurRadius: 22,
                              ),
                            ],
                          ),
                          child: forward ? next : current,
                        ),
                      ),
                    ],
                  );
                }
                if (!folding) {
                  return AnimatedSwitcher(
                    duration: widget.animate
                        ? const Duration(milliseconds: 180)
                        : Duration.zero,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeOutCubic,
                    child: current,
                  );
                }
                final _Fold fold = _Fold(size, _turn.value, _right, _grip, _dy);
                return Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    base,
                    ClipPath(clipper: _PageClip(fold.front), child: front),
                    spine,
                    // Cast onto the exposed page, below the lifted sheet.
                    IgnorePointer(
                      child: CustomPaint(painter: _FoldShadow(fold)),
                    ),
                    ClipPath(
                      clipper: _PageClip(fold.back),
                      child: Transform(transform: fold.matrix, child: back),
                    ),
                    IgnorePointer(
                      child: CustomPaint(painter: _FoldShade(fold)),
                    ),
                  ],
                );
              },
            ),
          ),
        );
        return Center(
          child: SizedBox.fromSize(
            size: size,
            child: Theme(data: paperTheme, child: book),
          ),
        );
      },
    );
  }
}

class _BookSpine extends CustomPainter {
  const _BookSpine();

  @override
  void paint(Canvas canvas, Size size) {
    final double c = size.width / 2;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(size.width, 0),
          <Color>[
            Colors.transparent,
            Colors.black.withValues(alpha: 0.025),
            Colors.black.withValues(alpha: 0.09),
            Colors.black.withValues(alpha: 0.23),
            Colors.black.withValues(alpha: 0.36),
            Colors.black.withValues(alpha: 0.23),
            Colors.black.withValues(alpha: 0.09),
            Colors.black.withValues(alpha: 0.025),
            Colors.transparent,
          ],
          const <double>[0, 0.15, 0.33, 0.46, 0.5, 0.54, 0.67, 0.85, 1],
        ),
    );
    canvas.drawLine(
      Offset(c, 0),
      Offset(c, size.height),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..strokeWidth = 0.8,
    );
  }

  @override
  bool shouldRepaint(_BookSpine oldDelegate) => false;
}

class _PaperGrain extends CustomPainter {
  _PaperGrain(this.image, this.color);
  final ui.Image image;
  final Color color;
  late final Paint _ink = Paint()
    ..shader = ui.ImageShader(
      image,
      TileMode.repeated,
      TileMode.repeated,
      Matrix4.identity().storage,
    )
    ..colorFilter = ui.ColorFilter.mode(color, BlendMode.srcIn);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, _ink);
  }

  @override
  bool shouldRepaint(_PaperGrain oldDelegate) =>
      oldDelegate.image != image || oldDelegate.color != color;
}

// Fold about the bisector between the held edge and the dragged edge.
// The next leaf is reflected twice so its text finishes upright.
class _Fold {
  _Fold(Size size, double value, bool right, double grip, double dy) {
    final double w = size.width;
    final double h = size.height;
    final double t = value.clamp(0.0001, 1);
    bind = Curves.easeOutCubic.transform(((t - 0.5) * 2).clamp(0, 1));
    strength = math.sin(math.pi * t);
    final Offset edge = Offset(right ? w : 0, grip);
    final Offset drag = Offset(
      edge.dx + (right ? -w : w) * t,
      grip + ((h / 2 - grip) * 0.5 + dy * 0.6) * strength * strength,
    );
    mid = (edge + drag) / 2;
    normal = (edge - drag) / (edge - drag).distance;
    lift = math.min(64, w * 0.075) * strength;
    final double bend = lift;
    final double x = right ? w / 2 : 0;
    final List<Offset> rect = <Offset>[
      Offset(x, 0),
      Offset(x + w / 2, 0),
      Offset(x + w / 2, h),
      Offset(x, h),
    ];
    front = _path(_clip(rect, false), bend);
    back = _path(
      _clip(
        rect,
        true,
      ).map((Offset p) => p - normal * (2 * _distance(p))).toList(),
      bend,
      crease,
    );
    final double nx = normal.dx;
    final double ny = normal.dy;
    final double k = 2 * (mid.dx * nx + mid.dy * ny);
    final double xx = 1 - 2 * nx * nx;
    final double xy = -2 * nx * ny;
    matrix = Matrix4.identity()
      ..setEntry(0, 0, -xx)
      ..setEntry(0, 1, xy)
      ..setEntry(1, 0, -xy)
      ..setEntry(1, 1, 1 - 2 * ny * ny)
      ..setEntry(0, 3, xx * w + k * nx)
      ..setEntry(1, 3, xy * w + k * ny);
  }

  late final Path front;
  late final Path back;
  late final Matrix4 matrix;
  late final Offset mid;
  late final Offset normal;
  late final double strength;
  late final double bind;
  late final double lift;
  final Path crease = Path();

  double _distance(Offset p) =>
      (p.dx - mid.dx) * normal.dx + (p.dy - mid.dy) * normal.dy;

  List<Offset> _clip(List<Offset> points, bool outer) {
    final List<Offset> result = <Offset>[];
    for (int i = 0; i < points.length; i++) {
      final Offset a = points[i];
      final Offset b = points[(i + 1) % points.length];
      final double da = _distance(a);
      final double db = _distance(b);
      final bool inside = outer ? da >= 0 : da <= 0;
      if (inside) result.add(a);
      if (inside != (outer ? db >= 0 : db <= 0)) {
        result.add(a + (b - a) * (da / (da - db)));
      }
    }
    return result;
  }

  Path _path(List<Offset> points, double bend, [Path? edge]) {
    final Path path = Path();
    if (points.isEmpty) return path;
    path.moveTo(points.first.dx, points.first.dy);
    for (int i = 0; i < points.length; i++) {
      final Offset a = points[i];
      final Offset b = points[(i + 1) % points.length];
      if (_distance(a).abs() < 0.01 && _distance(b).abs() < 0.01) {
        final Offset c = (a + b) / 2 + normal * bend;
        path.quadraticBezierTo(c.dx, c.dy, b.dx, b.dy);
        edge
          ?..moveTo(a.dx, a.dy)
          ..quadraticBezierTo(c.dx, c.dy, b.dx, b.dy);
      } else {
        path.lineTo(b.dx, b.dy);
      }
    }
    return path..close();
  }
}

class _PageClip extends CustomClipper<Path> {
  const _PageClip(this.path);
  final Path path;

  @override
  Path getClip(Size size) => path;

  @override
  bool shouldReclip(_PageClip oldClipper) => oldClipper.path != path;
}

class _FoldShadow extends CustomPainter {
  const _FoldShadow(this.fold);
  final _Fold fold;

  @override
  void paint(Canvas canvas, Size size) {
    final double s = fold.strength;
    final Offset n = fold.normal;
    final Offset along = Offset(-n.dy, n.dx) * 1e4;
    // The raised leaf drops a soft shadow on the page it still covers.
    canvas.save();
    canvas.clipPath(
      Path()..addPolygon(<Offset>[
        fold.mid + along,
        fold.mid - along,
        fold.mid - along - n * 1e4,
        fold.mid + along - n * 1e4,
      ], true),
    );
    canvas.translate(-n.dx * fold.lift * 0.2, 2 * s - n.dy * fold.lift * 0.2);
    canvas.drawPath(
      fold.back,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.24 * s)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1 + 7 * s),
    );
    canvas.restore();
    // The curl shades the page it uncovers, darkest right under the crease.
    final double reach = 12 + fold.lift * 1.6;
    canvas.drawPaint(
      Paint()
        ..shader = ui.Gradient.linear(
          fold.mid - n,
          fold.mid + n * reach,
          <Color>[
            Colors.transparent,
            Colors.black.withValues(alpha: 0.3 * s),
            Colors.black.withValues(alpha: 0.14 * s),
            Colors.black.withValues(alpha: 0.04 * s),
            Colors.transparent,
          ],
          <double>[0, 1 / (reach + 1), 0.3, 0.65, 1],
        ),
    );
    canvas.drawPath(
      fold.crease,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4 + 6 * s
        ..color = Colors.black.withValues(alpha: 0.3 * s)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2 + 6 * s),
    );
  }

  @override
  bool shouldRepaint(_FoldShadow oldDelegate) => true;
}

class _FoldShade extends CustomPainter {
  const _FoldShade(this.fold);
  final _Fold fold;

  @override
  void paint(Canvas canvas, Size size) {
    final double shade = fold.strength * (1 - fold.bind);
    final Offset crest = fold.mid + fold.normal * fold.lift * 0.5;
    final double width = 24 + fold.lift * 2.4;
    canvas.save();
    canvas.clipPath(fold.back);
    // A rolled sheet: dark where it turns away, a glossy band, then soft shade.
    canvas.drawPaint(
      Paint()
        ..shader = ui.Gradient.linear(
          crest,
          crest - fold.normal * width,
          <Color>[
            Colors.black.withValues(alpha: 0.3 * shade),
            Colors.black.withValues(alpha: 0.05 * shade),
            Colors.white.withValues(alpha: 0.3 * shade),
            Colors.white.withValues(alpha: 0),
            Colors.black.withValues(alpha: 0.1 * shade),
            Colors.black.withValues(alpha: 0),
          ],
          const <double>[0, 0.08, 0.2, 0.36, 0.62, 1],
        ),
    );
    // The landing leaf carries its gutter shade into the binding.
    canvas.drawPaint(
      Paint()
        ..shader = ui.Gradient.linear(
          fold.mid - fold.normal * 32,
          fold.mid,
          <Color>[
            Colors.transparent,
            Colors.black.withValues(alpha: 0.025 * fold.bind),
            Colors.black.withValues(alpha: 0.09 * fold.bind),
            Colors.black.withValues(alpha: 0.23 * fold.bind),
            Colors.black.withValues(alpha: 0.36 * fold.bind),
          ],
          const <double>[0, 0.3, 0.66, 0.92, 1],
        ),
    );
    canvas.restore();
    canvas.drawPath(
      fold.back,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.65
        ..color = Colors.black.withValues(alpha: 0.1 * fold.strength),
    );
    canvas.drawPath(
      fold.crease,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..color = Colors.white.withValues(alpha: 0.6 * shade),
    );
  }

  @override
  bool shouldRepaint(_FoldShade oldDelegate) => true;
}

// Hermite ease: leaves at [slope] times the average speed and lands at rest,
// so a released or tapped leaf keeps moving instead of stalling.
class _Release extends Curve {
  const _Release(this.slope);
  final double slope;

  @override
  double transformInternal(double t) =>
      t * t * (3 - 2 * t) + slope * t * (1 - t) * (1 - t);
}
