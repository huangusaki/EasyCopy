import 'package:flutter/widgets.dart';

class ReaderPinchZoomDetector extends StatefulWidget {
  const ReaderPinchZoomDetector({
    required this.child,
    required this.onPinchStart,
    required this.onPinchUpdate,
    required this.onPinchEnd,
    super.key,
  });

  final Widget child;
  final VoidCallback onPinchStart;
  final ValueChanged<double> onPinchUpdate;
  final VoidCallback onPinchEnd;

  @override
  State<ReaderPinchZoomDetector> createState() =>
      _ReaderPinchZoomDetectorState();
}

class _ReaderPinchZoomDetectorState extends State<ReaderPinchZoomDetector> {
  final Map<int, Offset> _pointers = <int, Offset>{};
  double? _initialDistance;
  bool _isPinchActive = false;

  double _pointerDistance() {
    if (_pointers.length < 2) {
      return 0;
    }
    final List<Offset> positions = _pointers.values.toList();
    return (positions[0] - positions[1]).distance;
  }

  void _handlePointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.position;
    if (_pointers.length == 2 && !_isPinchActive) {
      final double distance = _pointerDistance();
      if (distance > 0) {
        _initialDistance = distance;
        _isPinchActive = true;
        widget.onPinchStart();
      }
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) {
      return;
    }
    _pointers[event.pointer] = event.position;
    if (_isPinchActive &&
        _pointers.length >= 2 &&
        _initialDistance != null &&
        _initialDistance! > 0) {
      final double currentDistance = _pointerDistance();
      widget.onPinchUpdate(currentDistance / _initialDistance!);
    }
  }

  void _endPinchIfNeeded() {
    if (_isPinchActive && _pointers.length < 2) {
      _isPinchActive = false;
      _initialDistance = null;
      widget.onPinchEnd();
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    _pointers.remove(event.pointer);
    _endPinchIfNeeded();
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    _endPinchIfNeeded();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: widget.child,
    );
  }
}
