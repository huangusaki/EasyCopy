import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

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
    super.key,
  });

  final String contentKey;
  final int tabIndex;
  final int routeDepth;
  final Widget child;

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

  // 切 Tab 时旧页先淡出、新页稍后淡入，避免两页文字叠在一起。
  late final CurvedAnimation _tabEnterOpacity = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0.12, 0.7, curve: Curves.easeOut),
  );
  late final CurvedAnimation _tabExitProgress = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.35, curve: Curves.easeOut),
  );
  late final Animation<double> _tabExitOpacity = ReverseAnimation(
    _tabExitProgress,
  );
  final Tween<Offset> _exitSlideTween = Tween<Offset>(
    begin: Offset.zero,
    end: Offset.zero,
  );
  late final Animation<Offset> _exitSlide = _exitSlideTween.animate(_curve);

  final GlobalKey _boundaryKey = GlobalKey();
  ui.Image? _outgoing;
  bool _switchingTab = false;

  @override
  void initState() {
    super.initState();
    // 旧页淡出后立即释放截图，后半段不再空画透明图片。
    _controller.addListener(() {
      if (_outgoing != null && _tabExitOpacity.value == 0) {
        setState(() => _replaceOutgoing(null));
      }
    });
  }

  void _replaceOutgoing(ui.Image? image) {
    _outgoing?.dispose();
    _outgoing = image;
  }

  /// 旧页面已被新子树替换，只能从上一帧的图层截出画面。
  ui.Image? _captureOutgoing() {
    final RenderObject? boundary = _boundaryKey.currentContext
        ?.findRenderObject();
    if (boundary is! _RenderLastFrameBoundary) {
      return null;
    }
    return boundary.captureLastFrame(MediaQuery.devicePixelRatioOf(context));
  }

  @override
  void didUpdateWidget(covariant ContentSwitchTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.contentKey == widget.contentKey) {
      return;
    }

    _switchingTab = widget.tabIndex != oldWidget.tabIndex;
    _replaceOutgoing(_switchingTab ? _captureOutgoing() : null);
    if (_switchingTab) {
      final double direction = widget.tabIndex > oldWidget.tabIndex ? 1 : -1;
      _slideTween.begin = Offset(0.18 * direction, 0);
      _exitSlideTween.end = Offset(-0.18 * direction, 0);
      _scaleTween.begin = 1;
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
    _replaceOutgoing(null);
    _tabEnterOpacity.dispose();
    _tabExitProgress.dispose();
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ui.Image? outgoing = _outgoing;
    // 动画帧的重绘收在这一层内，不波及标题栏、导航栏等外层。
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          // 截图边界包住入场动画，连续切换时能接住半透明的中间态。
          _LastFrameBoundary(
            key: _boundaryKey,
            child: FadeTransition(
              opacity: _switchingTab ? _tabEnterOpacity : _curve,
              child: SlideTransition(
                position: _slide,
                child: ScaleTransition(
                  scale: _scale,
                  // 位移和缩放只变换已缓存的图层，不逐帧重绘页面。
                  child: RepaintBoundary(child: widget.child),
                ),
              ),
            ),
          ),
          if (outgoing != null)
            Positioned.fill(
              child: IgnorePointer(
                child: SlideTransition(
                  position: _exitSlide,
                  // 透明度直接画进图片，省掉一次离屏合成；截图按原分辨率 1:1 绘制，
                  // 双线性采样足够，避免 medium 触发 mipmap。
                  child: RawImage(
                    image: outgoing,
                    opacity: _tabExitOpacity,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.low,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _LastFrameBoundary extends SingleChildRenderObjectWidget {
  const _LastFrameBoundary({super.child, super.key});

  @override
  _RenderLastFrameBoundary createRenderObject(BuildContext context) {
    return _RenderLastFrameBoundary();
  }
}

class _RenderLastFrameBoundary extends RenderRepaintBoundary {
  /// 构建阶段子树可能已标脏，[toImageSync] 会断言；
  /// 但图层要到绘制阶段才更新，此时仍是屏幕上那一帧。
  ui.Image? captureLastFrame(double pixelRatio) {
    final ContainerLayer? layer = this.layer;
    if (!hasSize || layer is! OffsetLayer) {
      return null;
    }
    return layer.toImageSync(Offset.zero & size, pixelRatio: pixelRatio);
  }
}
