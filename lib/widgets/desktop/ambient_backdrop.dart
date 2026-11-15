import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 静态光斑背景，仅随鼠标做轻微视差。
///
/// 不再常驻动画：48 秒一圈的漂移肉眼几乎不可见，却让整窗每帧重绘，
/// 还连带上层 BackdropFilter（Dock）每帧重新模糊。
class AmbientBackdrop extends StatefulWidget {
  const AmbientBackdrop({required this.child, this.enabled = true, super.key});

  final Widget child;
  final bool enabled;

  @override
  State<AmbientBackdrop> createState() => _AmbientBackdropState();
}

class _AmbientBackdropState extends State<AmbientBackdrop> {
  final ValueNotifier<Offset> _pointer = ValueNotifier<Offset>(Offset.zero);

  @override
  void dispose() {
    _pointer.dispose();
    super.dispose();
  }

  void _handleHover(PointerEvent event, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    _pointer.value = Offset(
      (event.localPosition.dx / size.width) * 2 - 1,
      (event.localPosition.dy / size.height) * 2 - 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }

    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = constraints.biggest;
        return MouseRegion(
          opaque: false,
          hitTestBehavior: HitTestBehavior.translucent,
          onHover: (PointerHoverEvent event) => _handleHover(event, size),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _AmbientPainter(
                      pointer: _pointer,
                      colorScheme: colorScheme,
                    ),
                  ),
                ),
              ),
              Positioned.fill(child: widget.child),
            ],
          ),
        );
      },
    );
  }
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter({required this.pointer, required this.colorScheme})
    : super(repaint: pointer);

  final ValueNotifier<Offset> pointer;
  final ColorScheme colorScheme;

  bool get _isDark => colorScheme.brightness == Brightness.dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }

    canvas.drawRect(Offset.zero & size, Paint()..color = colorScheme.surface);

    final double alphaBoost = _isDark ? 1.25 : 1.0;
    final Offset pointerValue = pointer.value;

    void blob({
      required Color color,
      required double alpha,
      required Offset anchor,
      required double radiusFactor,
      required double driftFactor,
      required double phase,
      required double parallaxDepth,
    }) {
      final double drift = size.shortestSide * driftFactor;
      final Offset parallax = pointerValue * size.shortestSide * parallaxDepth;
      final Offset center =
          Offset(size.width * anchor.dx, size.height * anchor.dy) +
          Offset(math.cos(phase) * drift, math.sin(phase) * drift) +
          parallax;
      final double radius = size.shortestSide * radiusFactor;
      final Paint paint = Paint()
        ..shader = ui.Gradient.radial(center, radius, <Color>[
          color.withValues(alpha: (alpha * alphaBoost).clamp(0.0, 1.0)),
          color.withValues(alpha: 0.0),
        ]);
      canvas.drawCircle(center, radius, paint);
    }

    blob(
      color: colorScheme.primary,
      alpha: 0.16,
      anchor: const Offset(0.22, 0.26),
      radiusFactor: 0.62,
      driftFactor: 0.07,
      phase: 0,
      parallaxDepth: 0.030,
    );
    blob(
      color: colorScheme.secondary,
      alpha: 0.13,
      anchor: const Offset(0.82, 0.72),
      radiusFactor: 0.68,
      driftFactor: 0.09,
      phase: 1.9,
      parallaxDepth: 0.052,
    );
    blob(
      color: colorScheme.tertiary,
      alpha: 0.11,
      anchor: const Offset(0.42, 0.84),
      radiusFactor: 0.5,
      driftFactor: 0.06,
      phase: 4.1,
      parallaxDepth: 0.040,
    );
    blob(
      color: colorScheme.primaryContainer,
      alpha: 0.14,
      anchor: const Offset(0.86, 0.18),
      radiusFactor: 0.46,
      driftFactor: 0.08,
      phase: 2.8,
      parallaxDepth: 0.024,
    );

    final Paint sheen = Paint()
      ..shader =
          ui.Gradient.linear(Offset.zero, Offset(0, size.height), <Color>[
            (_isDark ? Colors.white : colorScheme.surfaceContainerLowest)
                .withValues(alpha: _isDark ? 0.02 : 0.30),
            Colors.transparent,
          ]);
    canvas.drawRect(Offset.zero & size, sheen);
  }

  @override
  bool shouldRepaint(covariant _AmbientPainter oldDelegate) {
    return oldDelegate.pointer != pointer ||
        oldDelegate.colorScheme != colorScheme;
  }
}
