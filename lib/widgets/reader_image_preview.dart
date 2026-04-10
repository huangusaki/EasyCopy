import 'package:flutter/material.dart';

typedef ReaderImageProviderBuilder =
    ImageProvider<Object> Function(String imageUrl);

class ReaderImagePreviewPagingController extends ChangeNotifier {
  ReaderImagePreviewPagingController({
    required this.itemCount,
    int initialIndex = 0,
  }) : _currentIndex = itemCount <= 0
           ? 0
           : initialIndex.clamp(0, itemCount - 1);

  final int itemCount;
  final Map<int, bool> _zoomStates = <int, bool>{};
  int _currentIndex;

  int get currentIndex => _currentIndex;

  bool get isCurrentPageZoomed => _zoomStates[_currentIndex] ?? false;

  bool get allowsPaging => !isCurrentPageZoomed;

  void setCurrentIndex(int index) {
    if (itemCount <= 0) {
      return;
    }
    final int nextIndex = index.clamp(0, itemCount - 1);
    if (_currentIndex == nextIndex) {
      return;
    }
    _currentIndex = nextIndex;
    notifyListeners();
  }

  void setPageZoomed(int index, bool isZoomed) {
    if (index < 0 || index >= itemCount) {
      return;
    }
    final bool currentState = _zoomStates[index] ?? false;
    if (currentState == isZoomed) {
      return;
    }
    if (isZoomed) {
      _zoomStates[index] = true;
    } else {
      _zoomStates.remove(index);
    }
    if (index == _currentIndex) {
      notifyListeners();
    }
  }
}

class ReaderImagePreviewScreen extends StatefulWidget {
  const ReaderImagePreviewScreen({
    super.key,
    required this.imageUrls,
    required this.initialIndex,
    required this.imageProviderBuilder,
    required this.onClose,
    this.onIndexChanged,
  });

  final List<String> imageUrls;
  final int initialIndex;
  final ReaderImageProviderBuilder imageProviderBuilder;
  final VoidCallback onClose;
  final ValueChanged<int>? onIndexChanged;

  @override
  State<ReaderImagePreviewScreen> createState() =>
      _ReaderImagePreviewScreenState();
}

class _ReaderImagePreviewScreenState extends State<ReaderImagePreviewScreen> {
  late final ReaderImagePreviewPagingController _pagingController =
      ReaderImagePreviewPagingController(
        itemCount: widget.imageUrls.length,
        initialIndex: widget.initialIndex,
      );
  late final PageController _pageController = PageController(
    initialPage: _pagingController.currentIndex,
  );

  @override
  void dispose() {
    _pageController.dispose();
    _pagingController.dispose();
    super.dispose();
  }

  void _handleZoomChanged(int index, bool isZoomed) {
    _pagingController.setPageZoomed(index, isZoomed);
  }

  @override
  Widget build(BuildContext context) {
    final EdgeInsets viewPadding = MediaQuery.viewPaddingOf(context);
    return Material(
      color: Colors.black,
      child: AnimatedBuilder(
        animation: _pagingController,
        builder: (BuildContext context, Widget? child) {
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              PageView.builder(
                key: const ValueKey<String>('reader-image-preview-page-view'),
                controller: _pageController,
                physics: _pagingController.allowsPaging
                    ? const BouncingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                itemCount: widget.imageUrls.length,
                onPageChanged: (int index) {
                  _pagingController.setCurrentIndex(index);
                  widget.onIndexChanged?.call(index);
                },
                itemBuilder: (BuildContext context, int index) {
                  return _ReaderImagePreviewPage(
                    key: ValueKey<String>(
                      'reader-image-preview-${widget.imageUrls[index]}',
                    ),
                    imageProvider: widget.imageProviderBuilder(
                      widget.imageUrls[index],
                    ),
                    onZoomChanged: (bool isZoomed) {
                      _handleZoomChanged(index, isZoomed);
                    },
                  );
                },
              ),
              Positioned(
                left: 12,
                top: viewPadding.top + 12,
                child: IconButton(
                  key: const ValueKey<String>('reader-image-preview-close'),
                  onPressed: widget.onClose,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.36),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.close_rounded),
                  tooltip: '关闭预览',
                ),
              ),
              Positioned(
                right: 12,
                top: viewPadding.top + 14,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.36),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    child: Text(
                      '${_pagingController.currentIndex + 1} / ${widget.imageUrls.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ReaderImagePreviewPage extends StatefulWidget {
  const _ReaderImagePreviewPage({
    super.key,
    required this.imageProvider,
    required this.onZoomChanged,
  });

  final ImageProvider<Object> imageProvider;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ReaderImagePreviewPage> createState() =>
      _ReaderImagePreviewPageState();
}

class _ReaderImagePreviewPageState extends State<_ReaderImagePreviewPage> {
  late final TransformationController _transformationController =
      TransformationController();
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _transformationController.addListener(_handleTransformChanged);
  }

  @override
  void dispose() {
    widget.onZoomChanged(false);
    _transformationController.removeListener(_handleTransformChanged);
    _transformationController.dispose();
    super.dispose();
  }

  void _handleTransformChanged() {
    final bool isZoomed =
        _transformationController.value.getMaxScaleOnAxis() > 1.01;
    if (_isZoomed == isZoomed) {
      return;
    }
    _isZoomed = isZoomed;
    widget.onZoomChanged(isZoomed);
    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildProgressIndicator() {
    return const Center(
      child: CircularProgressIndicator.adaptive(
        valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return InteractiveViewer(
          transformationController: _transformationController,
          minScale: 1,
          maxScale: 4,
          panEnabled: _isZoomed,
          scaleEnabled: true,
          clipBehavior: Clip.none,
          boundaryMargin: EdgeInsets.symmetric(
            horizontal: constraints.maxWidth,
            vertical: constraints.maxHeight,
          ),
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: Image(
              image: widget.imageProvider,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              frameBuilder:
                  (
                    BuildContext context,
                    Widget child,
                    int? frame,
                    bool wasSynchronouslyLoaded,
                  ) {
                    if (wasSynchronouslyLoaded || frame != null) {
                      return child;
                    }
                    return _buildProgressIndicator();
                  },
              errorBuilder:
                  (BuildContext context, Object error, StackTrace? stackTrace) {
                    return const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        size: 40,
                        color: Colors.white70,
                      ),
                    );
                  },
            ),
          ),
        );
      },
    );
  }
}
