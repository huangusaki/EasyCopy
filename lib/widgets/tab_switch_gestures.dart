import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class TabSwitchGestures extends StatefulWidget {
  const TabSwitchGestures({
    required this.onStep,
    required this.child,
    this.canStep,
    super.key,
  });

  final ValueChanged<int> onStep;

  /// 返回 false 时该方向只回弹，不切换。
  final bool Function(int step)? canStep;
  final Widget child;

  @override
  State<TabSwitchGestures> createState() => _TabSwitchGesturesState();
}

class _TabSwitchGesturesState extends State<TabSwitchGestures>
    with SingleTickerProviderStateMixin {
  late final AnimationController _offset = AnimationController.unbounded(
    vsync: this,
  );
  double _dragDistance = 0;
  double _scrollDistance = 0;
  bool _scrollSwitched = false;
  Timer? _scrollEndTimer;

  // 跟手位移上限，拖动开始时按宽度记下。
  double _followLimit = 0;

  bool _canStep(int step) => widget.canStep?.call(step) ?? true;

  /// 阻尼跟手；没有相邻 Tab 时只给一点橡皮筋提示。
  double _followOffset(double distance) {
    final bool blocked = !_canStep(distance < 0 ? 1 : -1);
    final double limit = _followLimit * (blocked ? 0.2 : 1);
    final double damped = distance.abs() * (blocked ? 0.3 : 0.7);
    if (limit <= 0) {
      return 0;
    }
    return distance.sign * limit * damped / (damped + limit);
  }

  void _startDrag(DragStartDetails details) {
    _offset.stop();
    _dragDistance = 0;
    _followLimit = (context.size?.width ?? 0) * 0.2;
  }

  void _updateDrag(DragUpdateDetails details) {
    _dragDistance += details.primaryDelta!;
    _offset.value = _followOffset(_dragDistance);
  }

  void _endDrag(DragEndDetails details) {
    final double velocity = details.primaryVelocity ?? 0;
    final double threshold = (MediaQuery.sizeOf(context).width * 0.15).clamp(
      56,
      112,
    );
    final double distance = _dragDistance;
    _dragDistance = 0;
    final bool fling = velocity.abs() >= 650 && distance.abs() >= 24;
    final int step = (fling ? velocity : distance) < 0 ? 1 : -1;
    if ((distance.abs() >= threshold || fling) && _canStep(step)) {
      // 当前帧的偏移已被页面切换动画截图接住，这里直接归位给新页面。
      _offset.value = 0;
      widget.onStep(step);
      return;
    }
    _settle();
  }

  void _cancelDrag() {
    _dragDistance = 0;
    _settle();
  }

  void _settle() {
    if (_offset.value == 0) {
      return;
    }
    unawaited(
      _offset.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        event.scrollDelta.dx.abs() <= event.scrollDelta.dy.abs()) {
      return;
    }
    // 内层横向列表优先消费，避免滑动列表时切换主 Tab。
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final double delta = (event as PointerScrollEvent).scrollDelta.dx;
      _scrollEndTimer?.cancel();
      _scrollEndTimer = Timer(const Duration(milliseconds: 220), () {
        _scrollDistance = 0;
        _scrollSwitched = false;
      });
      if (_scrollSwitched) {
        return;
      }
      if (delta.sign != _scrollDistance.sign) {
        _scrollDistance = 0;
      }
      _scrollDistance += delta;
      if (_scrollDistance.abs() >= 64) {
        _scrollSwitched = true;
        widget.onStep(_scrollDistance > 0 ? 1 : -1);
      }
    });
  }

  @override
  void dispose() {
    _scrollEndTimer?.cancel();
    _offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      dragStartBehavior: DragStartBehavior.down,
      onHorizontalDragStart: _startDrag,
      onHorizontalDragUpdate: _updateDrag,
      onHorizontalDragEnd: _endDrag,
      onHorizontalDragCancel: _cancelDrag,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerSignal: _handlePointerSignal,
        onPointerCancel: (_) => _dragDistance = 0,
        child: AnimatedBuilder(
          animation: _offset,
          builder: (BuildContext context, Widget? child) {
            return Transform.translate(
              offset: Offset(_offset.value, 0),
              child: child,
            );
          },
          // 拖动每帧只平移已缓存的图层，不重绘页面；不叠透明度，免得每帧离屏合成。
          child: RepaintBoundary(child: widget.child),
        ),
      ),
    );
  }
}
