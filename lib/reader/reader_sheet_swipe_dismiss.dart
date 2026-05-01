import 'package:flutter/widgets.dart';

class ReaderSheetSwipeDismissRegion extends StatefulWidget {
  const ReaderSheetSwipeDismissRegion({
    required this.child,
    required this.onDismiss,
    required this.dismissDistance,
    super.key,
  });

  final Widget child;
  final VoidCallback onDismiss;
  final double dismissDistance;

  @override
  State<ReaderSheetSwipeDismissRegion> createState() =>
      _ReaderSheetSwipeDismissRegionState();
}

class _ReaderSheetSwipeDismissRegionState
    extends State<ReaderSheetSwipeDismissRegion> {
  Offset? _pointerDownPosition;
  bool _dismissTriggered = false;

  void _resetGesture() {
    _pointerDownPosition = null;
    _dismissTriggered = false;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    final Offset? pointerDownPosition = _pointerDownPosition;
    if (pointerDownPosition == null || _dismissTriggered) {
      return;
    }
    final Offset delta = event.position - pointerDownPosition;
    final bool isDominantDownwardSwipe =
        delta.dy >= widget.dismissDistance && delta.dy > delta.dx.abs() * 1.2;
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
        _pointerDownPosition = event.position;
        _dismissTriggered = false;
      },
      onPointerMove: _handlePointerMove,
      onPointerUp: (_) => _resetGesture(),
      onPointerCancel: (_) => _resetGesture(),
      child: widget.child,
    );
  }
}
