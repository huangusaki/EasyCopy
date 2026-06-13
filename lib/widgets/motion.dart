import 'package:flutter/material.dart';

class StaggerIn extends StatefulWidget {
  const StaggerIn({
    required this.child,
    this.index = 0,
    this.enabled = true,
    this.step = const Duration(milliseconds: 26),
    super.key,
  });

  static const int _maxStaggerSteps = 12;

  final Widget child;
  final int index;
  final bool enabled;
  final Duration step;

  @override
  State<StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<StaggerIn>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  CurvedAnimation? _curve;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) {
      return;
    }
    final AnimationController controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _controller = controller;
    _curve = CurvedAnimation(parent: controller, curve: Curves.easeOutCubic);
    final int stepCount = widget.index.clamp(0, StaggerIn._maxStaggerSteps);
    if (stepCount == 0) {
      controller.forward();
      return;
    }
    Future<void>.delayed(widget.step * stepCount, () {
      if (mounted) {
        controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _curve?.dispose();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final CurvedAnimation? curve = _curve;
    if (curve == null) {
      return widget.child;
    }
    return AnimatedBuilder(
      animation: curve,
      builder: (BuildContext context, Widget? child) {
        final double t = curve.value;
        if (t >= 1) {
          return child!;
        }
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 18 * (1 - t)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

class ContentSwitchTransition extends StatefulWidget {
  const ContentSwitchTransition({
    required this.contentKey,
    required this.tabIndex,
    required this.routeDepth,
    required this.child,
    this.reducedMotion = false,
    super.key,
  });

  final String contentKey;
  final int tabIndex;
  final int routeDepth;
  final Widget child;
  final bool reducedMotion;

  @override
  State<ContentSwitchTransition> createState() =>
      _ContentSwitchTransitionState();
}

class _ContentSwitchTransitionState extends State<ContentSwitchTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
    value: 1,
  );

  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutQuart,
  );

  final Tween<Offset> _slideTween = Tween<Offset>(
    begin: Offset.zero,
    end: Offset.zero,
  );
  final Tween<double> _scaleTween = Tween<double>(begin: 1, end: 1);

  late final Animation<Offset> _slide = _slideTween.animate(_curve);
  late final Animation<double> _scale = _scaleTween.animate(_curve);

  @override
  void didUpdateWidget(covariant ContentSwitchTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contentKey == widget.contentKey) {
      return;
    }

    if (widget.reducedMotion) {
      _scaleTween.begin = 1;
      if (widget.tabIndex != oldWidget.tabIndex) {
        final bool movingRight = widget.tabIndex > oldWidget.tabIndex;
        _controller.duration = const Duration(milliseconds: 240);
        _slideTween.begin = Offset(movingRight ? 0.06 : -0.06, 0);
        _controller.forward(from: 0);
        return;
      }
      _controller.duration = const Duration(milliseconds: 220);
      _slideTween.begin = Offset.zero;
      _controller.forward(from: 0.35);
      return;
    }

    _controller.duration = const Duration(milliseconds: 400);
    if (widget.tabIndex != oldWidget.tabIndex) {
      final bool movingRight = widget.tabIndex > oldWidget.tabIndex;
      _slideTween.begin = Offset(movingRight ? 0.045 : -0.045, 0);
      _scaleTween.begin = 0.982;
    } else if (widget.routeDepth > oldWidget.routeDepth) {
      _slideTween.begin = const Offset(0, 0.026);
      _scaleTween.begin = 0.988;
    } else if (widget.routeDepth < oldWidget.routeDepth) {
      _slideTween.begin = const Offset(0, -0.018);
      _scaleTween.begin = 1.014;
    } else {
      _slideTween.begin = const Offset(0, 0.012);
      _scaleTween.begin = 0.996;
    }

    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reducedMotion) {
      return FadeTransition(
        opacity: _curve,
        child: SlideTransition(position: _slide, child: widget.child),
      );
    }
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: _slide,
        child: ScaleTransition(scale: _scale, child: widget.child),
      ),
    );
  }
}
