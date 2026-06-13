import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class AmbientBackdrop extends StatefulWidget {
  const AmbientBackdrop({required this.child, this.enabled = true, super.key});

  final Widget child;
  final bool enabled;

  @override
  State<AmbientBackdrop> createState() => _AmbientBackdropState();
}

class _AmbientBackdropState extends State<AmbientBackdrop>
    with SingleTickerProviderStateMixin, WindowListener {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 48),
  );

  Offset _pointerTarget = Offset.zero;
  Offset _pointer = Offset.zero;

  bool _isWindowFocused = true;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant AmbientBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled != oldWidget.enabled) {
      _syncAnimation();
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void onWindowFocus() {
    _isWindowFocused = true;
    _syncAnimation();
  }

  @override
  void onWindowBlur() {
    _isWindowFocused = false;
    _syncAnimation();
  }

  void _syncAnimation() {
    final bool shouldRun = widget.enabled && _isWindowFocused;
    if (shouldRun && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!shouldRun && _controller.isAnimating) {
      _controller.stop();
    }
  }

  void _handleHover(PointerEvent event, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return;
    }
    _pointerTarget = Offset(
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
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (BuildContext context, Widget? _) {
                      _pointer = Offset.lerp(_pointer, _pointerTarget, 0.05)!;
                      return CustomPaint(
                        isComplex: true,
                        willChange: true,
                        painter: _AmbientPainter(
                          progress: _controller.value,
                          pointer: _pointer,
                          colorScheme: colorScheme,
                        ),
                      );
                    },
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
  const _AmbientPainter({
    required this.progress,
    required this.pointer,
    required this.colorScheme,
  });

  final double progress;
  final Offset pointer;
  final ColorScheme colorScheme;

  bool get _isDark => colorScheme.brightness == Brightness.dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }

    canvas.drawRect(Offset.zero & size, Paint()..color = colorScheme.surface);

    final double t = progress * 2 * math.pi;
    final double alphaBoost = _isDark ? 1.25 : 1.0;

    void blob({
      required Color color,
      required double alpha,
      required Offset anchor,
      required double radiusFactor,
      required double driftFactor,
      required double phase,
      required double speed,
      required double parallaxDepth,
    }) {
      final double drift = size.shortestSide * driftFactor;
      final Offset parallax = pointer * size.shortestSide * parallaxDepth;
      final Offset center =
          Offset(size.width * anchor.dx, size.height * anchor.dy) +
          Offset(
            math.cos(t * speed + phase) * drift,
            math.sin(t * speed + phase) * drift,
          ) +
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
      speed: 1,
      parallaxDepth: 0.030,
    );
    blob(
      color: colorScheme.secondary,
      alpha: 0.13,
      anchor: const Offset(0.82, 0.72),
      radiusFactor: 0.68,
      driftFactor: 0.09,
      phase: 1.9,
      speed: 0.8,
      parallaxDepth: 0.052,
    );
    blob(
      color: colorScheme.tertiary,
      alpha: 0.11,
      anchor: const Offset(0.42, 0.84),
      radiusFactor: 0.5,
      driftFactor: 0.06,
      phase: 4.1,
      speed: 1.2,
      parallaxDepth: 0.040,
    );
    blob(
      color: colorScheme.primaryContainer,
      alpha: 0.14,
      anchor: const Offset(0.86, 0.18),
      radiusFactor: 0.46,
      driftFactor: 0.08,
      phase: 2.8,
      speed: 0.6,
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
    return oldDelegate.progress != progress ||
        oldDelegate.pointer != pointer ||
        oldDelegate.colorScheme != colorScheme;
  }
}
