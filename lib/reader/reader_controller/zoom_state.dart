class ReaderZoomController {
  static const String viewportZoomKey = '__viewport_zoom__';

  final Set<String> _zoomedImageKeys = <String>{};

  bool _isScaleGestureActive = false;
  double _scale = 1.0;
  double _baseScale = 1.0;
  double _panOffsetX = 0;
  double _panOffsetY = 0;

  bool get isScaleGestureActive => _isScaleGestureActive;
  bool get isLocked => _isScaleGestureActive || _zoomedImageKeys.isNotEmpty;
  double get scale => _scale;
  double get panOffsetX => _panOffsetX;
  double get panOffsetY => _panOffsetY;

  bool startPinch() {
    _baseScale = _scale;
    return _setScaleGestureActive(true);
  }

  bool updatePinch(double relativeScale) {
    final double nextScale = (_baseScale * relativeScale).clamp(1.0, 4.0);
    if ((nextScale - _scale).abs() < 0.005) {
      return false;
    }
    _scale = nextScale;
    return true;
  }

  bool endPinch() {
    bool changed = _setScaleGestureActive(false);
    if (_scale <= 1.02) {
      changed = _resetViewportZoom() || changed;
    } else {
      changed = setImageZoomed(viewportZoomKey, true) || changed;
    }
    return changed;
  }

  bool updatePanOffset({required double x, required double y}) {
    if (_panOffsetX == x && _panOffsetY == y) {
      return false;
    }
    _panOffsetX = x;
    _panOffsetY = y;
    return true;
  }

  bool setImageZoomed(String imageKey, bool isZoomed) {
    final bool alreadyZoomed = _zoomedImageKeys.contains(imageKey);
    if (alreadyZoomed == isZoomed) {
      return false;
    }
    if (isZoomed) {
      _zoomedImageKeys.add(imageKey);
    } else {
      _zoomedImageKeys.remove(imageKey);
    }
    return true;
  }

  bool reset() {
    if (!_isScaleGestureActive && _zoomedImageKeys.isEmpty && _scale <= 1.01) {
      return false;
    }
    _isScaleGestureActive = false;
    _zoomedImageKeys.clear();
    _scale = 1.0;
    _panOffsetX = 0;
    _panOffsetY = 0;
    return true;
  }

  bool _setScaleGestureActive(bool value) {
    if (_isScaleGestureActive == value) {
      return false;
    }
    _isScaleGestureActive = value;
    return true;
  }

  bool _resetViewportZoom() {
    bool changed = false;
    if (_scale != 1.0) {
      _scale = 1.0;
      changed = true;
    }
    if (_panOffsetX != 0 || _panOffsetY != 0) {
      _panOffsetX = 0;
      _panOffsetY = 0;
      changed = true;
    }
    changed = _zoomedImageKeys.remove(viewportZoomKey) || changed;
    return changed;
  }
}
