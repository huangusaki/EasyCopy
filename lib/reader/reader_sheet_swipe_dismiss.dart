import 'dart:math' as math;

import 'package:flutter/widgets.dart';

const double _minimumSheetDismissDistance = 120;

class ReaderSheetSwipeDismissRegion extends StatefulWidget {
  const ReaderSheetSwipeDismissRegion({
    required this.child,
    required this.onDismiss,
    required this.dismissDistance,
    this.canDismiss,
    super.key,
  });

  final Widget child;
  final VoidCallback onDismiss;
  final double dismissDistance;

  /// 手势是否可用。
  ///
  /// 这里用的是 [Listener]，不进手势竞技场，所以弹窗内部的列表在滚动时它照样能
  /// 收到指针移动——不加约束的话，滚列表滚到累计下移超过阈值就会把弹窗一起甩掉。
  /// 调用方用它把手势限制在"列表已经停在顶部"的场景。
  final ValueGetter<bool>? canDismiss;

  @override
  State<ReaderSheetSwipeDismissRegion> createState() =>
      _SheetSwipeDismissState();
}

class _SheetSwipeDismissState extends State<ReaderSheetSwipeDismissRegion> {
  Offset? _pointerDownPosition;
  bool _dismissTriggered = false;

  bool get _isDismissAllowed => widget.canDismiss?.call() ?? true;

  void _resetGesture() {
    _pointerDownPosition = null;
    _dismissTriggered = false;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final Offset? pointerDownPosition = _pointerDownPosition;
    if (pointerDownPosition == null || _dismissTriggered) {
      return;
    }
    // 手势中途列表滚离了顶部，就把这一整段作废：此时用户的意图是滚列表。
    // 置空 _pointerDownPosition 而不是直接 return，避免松手前又滚回顶部时
    // 拿一个很早的按下点去比距离，一下就越过阈值。
    if (!_isDismissAllowed) {
      _pointerDownPosition = null;
      return;
    }
    final Offset delta = event.position - pointerDownPosition;
    final double effectiveDismissDistance = math.max(
      widget.dismissDistance,
      _minimumSheetDismissDistance,
    );
    final bool isDominantDownwardSwipe =
        delta.dy >= effectiveDismissDistance && delta.dy > delta.dx.abs() * 1.2;
    if (!isDominantDownwardSwipe) {
      return;
    }
    _dismissTriggered = true;
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (PointerDownEvent event) {
        _dismissTriggered = false;
        _pointerDownPosition = _isDismissAllowed ? event.position : null;
      },
      onPointerMove: _handlePointerMove,
      onPointerUp: (_) => _resetGesture(),
      onPointerCancel: (_) => _resetGesture(),
      child: widget.child,
    );
  }
}
