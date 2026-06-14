import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:reader/models/app_preferences.dart';
import 'package:reader/models/chapter_comment.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/reader/internal/reader_comment_layout.dart';
import 'package:reader/reader/internal/reader_paged_scroll_physics.dart';
import 'package:reader/reader/reader_controller.dart';
import 'package:reader/reader/reader_image.dart';
import 'package:reader/reader/reader_pinch_zoom.dart';
import 'package:reader/reader/reader_progress_seek_bar.dart';
import 'package:reader/reader/reader_sheet_swipe_dismiss.dart';
import 'package:reader/reader/reader_status_label.dart';
import 'package:reader/services/app_preferences_controller.dart';
import 'package:reader/services/document_tree_image_provider.dart';
import 'package:reader/services/image_cache.dart';
import 'package:reader/services/local_library_store.dart';
import 'package:reader/services/reader_comment_utils.dart';
import 'package:reader/services/reader_history_recorder.dart';
import 'package:reader/services/reader_platform_bridge.dart';
import 'package:reader/services/reader_progress_store.dart';
import 'package:reader/services/site_api_client.dart';
import 'package:reader/services/site_session.dart';
import 'package:reader/services/tree_image_provider.dart';
import 'package:reader/widgets/responsive_layout.dart';
import 'package:reader/widgets/settings_ui.dart';
import 'package:reader/widgets/top_notice.dart';

part 'reader_screen/chapter_boundary.dart';
part 'reader_screen/comment_cloud.dart';
part 'reader_screen/settings_sheet.dart';

const Duration _readerExitFadeDuration = Duration(milliseconds: 220);
const double _uiToggleInsetRatio = 0.075;
const double _tapTurnSideZoneRatio = 0.33;
const double _settingsDismissDistance = 72;
const double _instantPageSwipeDistance = 72;
const double _instantPageSwipeVelocity = 220;

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    required this.page,
    required this.isExitTransitionActive,
    required this.onRequestChapterNavigation,
    required this.onRequestAuth,
    required this.onLogoutForExpiredSession,
    required this.onResolveHistoryCover,
    this.openAtEnd = false,
    this.onOpenAtEndConsumed,
    super.key,
  });

  final ReaderPageData page;
  final bool isExitTransitionActive;
  final ReaderChapterNavigationCallback onRequestChapterNavigation;
  final Future<void> Function() onRequestAuth;
  final Future<void> Function() onLogoutForExpiredSession;
  final ResolveReaderHistoryCover onResolveHistoryCover;

  /// 本章打开后定位末页。
  final bool openAtEnd;

  /// 清除末页定位意图。
  final VoidCallback? onOpenAtEndConsumed;

  @override
  State<ReaderScreen> createState() => ReaderScreenState();
}

class ReaderScreenState extends State<ReaderScreen> {
  late final ReaderController _controller;
  double _instantPageDragDx = 0;

  ReaderController get controller => _controller;

  @override
  void initState() {
    super.initState();
    _controller = ReaderController(
      preferencesController: AppPreferencesController.instance,
      progressStore: ReaderProgressStore.instance,
      platformBridge: ReaderPlatformBridge.instance,
      apiClient: SiteApiClient.instance,
      session: SiteSession.instance,
      localLibraryStore: LocalLibraryStore.instance,
      historyRecorder: ReaderHistoryRecorder(
        resolveCoverUrl: widget.onResolveHistoryCover,
      ),
      onRequestChapterNavigation: widget.onRequestChapterNavigation,
      onRequestAuth: widget.onRequestAuth,
      onLogoutForExpiredSession: widget.onLogoutForExpiredSession,
      onShowMessage: _showNotice,
    );
    _controller.attachPlatformSubscriptions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.setPage(widget.page, openAtEnd: widget.openAtEnd);
      _consumeOpenAtEndIntent();
    });
  }

  @override
  void didUpdateWidget(covariant ReaderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.page, widget.page)) {
      _controller.setPage(
        widget.page,
        previousUri: oldWidget.page.uri,
        openAtEnd: widget.openAtEnd,
      );
      _consumeOpenAtEndIntent();
    }
  }

  void _consumeOpenAtEndIntent() {
    // 阅读器切换到新章节后，无论本次是否使用了 openAtEnd，都通知上层清除
    // 这个一次性意图：避免加载失败 / 被其它导航打断 / 经目录等入口再次打开
    // 同一章节时，残留的 key 误判 openAtEnd 直接跳到末页。
    widget.onOpenAtEndConsumed?.call();
  }

  @override
  void dispose() {
    _controller.dispose();
    unawaited(_controller.restoreDefaultEnvironment());
    super.dispose();
  }

  void _showNotice(String message) {
    if (!mounted) return;
    TopNotice.show(context, message, tone: TopNotice.toneForMessage(message));
  }

  void _handleReaderTapUp(TapUpDetails details) {
    final BuildContext? viewportContext =
        _controller.viewportKey.currentContext;
    final RenderBox? renderBox =
        viewportContext?.findRenderObject() as RenderBox?;
    final double viewportWidth = renderBox != null && renderBox.hasSize
        ? renderBox.size.width
        : MediaQuery.sizeOf(context).width;
    final double viewportHeight = renderBox != null && renderBox.hasSize
        ? renderBox.size.height
        : details.localPosition.dy * 2;
    final double dx = details.localPosition.dx;
    final double dy = details.localPosition.dy;
    final ReaderPreferences preferences = _controller.preferences;

    if (preferences.tapToTurnPage) {
      final double sideZoneWidth = viewportWidth * _tapTurnSideZoneRatio;
      if (dx <= sideZoneWidth) {
        _handleTapPageTurn(tappedLeft: true);
        return;
      }
      if (dx >= viewportWidth - sideZoneWidth) {
        _handleTapPageTurn(tappedLeft: false);
        return;
      }
      _handleReaderMenuTap(dy <= viewportHeight * 0.5);
      return;
    }

    final double uiToggleInsetWidth = viewportWidth * _uiToggleInsetRatio;
    if (dx <= uiToggleInsetWidth || dx >= viewportWidth - uiToggleInsetWidth) {
      return;
    }
    _handleReaderMenuTap(dy <= viewportHeight * 0.5);
  }

  void _handleReaderMenuTap(bool isTopHalf) {
    if (isTopHalf) {
      _controller.hideChapterControls();
      unawaited(_showReaderSettingsSheet());
      return;
    }
    _controller.toggleChapterControls();
  }

  void _handleTapPageTurn({required bool tappedLeft}) {
    _controller.hideChapterControls();
    final bool isRightToLeft =
        _controller.preferences.readingDirection ==
        ReaderReadingDirection.rightToLeft;
    final bool forward = isRightToLeft ? tappedLeft : !tappedLeft;
    if (forward) {
      unawaited(_controller.stepForward());
    } else {
      unawaited(_controller.stepBackward());
    }
  }

  Future<void> _showReaderSettingsSheet() async {
    if (_controller.isSettingsOpen) return;
    _controller.setSettingsSheetOpen(true);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
      builder: _buildReaderSettingsSheet,
    );
    _controller.setSettingsSheetOpen(false);
  }

  Widget _buildReaderOverlay(BuildContext context, ReaderPageData page) {
    final EdgeInsets viewPadding = MediaQuery.viewPaddingOf(context);
    final ReaderPreferences preferences = _controller.preferences;
    final double topOffset = preferences.fullscreen ? 2 : viewPadding.top + 6;
    final int? batteryLevel = _controller.batteryLevel;
    return IgnorePointer(
      child: Stack(
        children: <Widget>[
          if (_controller.platformBridge.isAndroidSupported &&
              preferences.showBattery)
            Positioned(
              left: 8,
              top: topOffset,
              child: ReaderStatusLabel(
                label: batteryLevel == null ? '--%' : '$batteryLevel%',
                icon: Icons.bolt_rounded,
                fontSize: 14,
              ),
            ),
          if (preferences.showClock)
            Positioned(
              right: 8,
              top: topOffset,
              child: const _ReaderClockLabel(),
            ),
          if (preferences.showProgress)
            Positioned(
              left: 0,
              right: 0,
              top: topOffset,
              child: Center(
                child: ReaderStatusLabel(
                  label: _readerPageCountLabel(page),
                  fontSize: 15,
                ),
              ),
            ),
          if (page.nextHref.trim().isNotEmpty)
            _buildNextChapterCue(context, page),
        ],
      ),
    );
  }

  String _readerPageCountLabel(ReaderPageData page) {
    if (page.imageUrls.isEmpty) return '--/--';
    final ReaderPreferences preferences = _controller.preferences;
    final int visibleIndex =
        (preferences.isPaged
                ? _controller.currentPageIndex
                : _controller.visibleImageIndex)
            .clamp(0, page.imageUrls.length - 1);
    return '${visibleIndex + 1}/${page.imageUrls.length}';
  }

  Widget _buildReaderChapterControls(
    BuildContext context,
    ReaderPageData page,
  ) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final ReaderPreferences preferences = _controller.preferences;
    final int imageCount = page.imageUrls.length;
    final bool showSeekBar = imageCount > 1;
    final int currentImageIndex = imageCount == 0
        ? 0
        : (preferences.isPaged
                  ? _controller.currentPageIndex
                  : _controller.visibleImageIndex)
              .clamp(0, imageCount - 1);
    return AppSurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (showSeekBar) ...<Widget>[
            ReaderProgressSeekBar(
              currentIndex: currentImageIndex,
              totalCount: imageCount,
              onInteraction: () {
                _controller.noteUserInteraction();
                _controller.cancelAutoTurn();
              },
              onSeek: (int index) =>
                  _seekReaderToImageIndex(context, page, index),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.tonal(
                  onPressed: page.prevHref.isEmpty
                      ? null
                      : () => unawaited(_navigateToHref(page.prevHref, page)),
                  child: const Text('上一话'),
                ),
              ),
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 88, maxWidth: 120),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (page.chapterTitle.isNotEmpty)
                      Text(
                        page.chapterTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.66),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: page.nextHref.isEmpty
                      ? null
                      : () => unawaited(_navigateToHref(page.nextHref, page)),
                  child: const Text('下一话'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _navigateToHref(String href, ReaderPageData currentPage) {
    final bool isPrev = currentPage.prevHref == href;
    return widget.onRequestChapterNavigation(
      href,
      prevHref: isPrev ? '' : currentPage.uri,
      nextHref: isPrev ? currentPage.uri : '',
      catalogHref: currentPage.catalogHref,
      openAtEnd: isPrev,
    );
  }

  void goToNextChapter() {
    final ReaderPageData page = widget.page;
    if (page.nextHref.trim().isEmpty) return;
    unawaited(_navigateToHref(page.nextHref, page));
  }

  void goToPreviousChapter() {
    final ReaderPageData page = widget.page;
    if (page.prevHref.trim().isEmpty) return;
    unawaited(_navigateToHref(page.prevHref, page));
  }

  void _seekReaderToImageIndex(
    BuildContext context,
    ReaderPageData page,
    int imageIndex,
  ) {
    if (_controller.isZoomGestureLocked || page.imageUrls.isEmpty) return;
    final int clampedIndex = imageIndex.clamp(0, page.imageUrls.length - 1);
    final double estimatedOffset = _estimateOffsetForImage(
      context,
      page,
      clampedIndex,
    );
    _controller.seekToImageIndex(
      page: page,
      imageIndex: clampedIndex,
      estimatedScrollOffset: estimatedOffset,
    );
  }

  double _estimateOffsetForImage(
    BuildContext context,
    ReaderPageData page,
    int imageIndex,
  ) {
    final Size screenSize = MediaQuery.sizeOf(context);
    final ReaderPreferences preferences = _controller.preferences;
    final bool showGap = preferences.showPageGap;
    final double topPadding = preferences.fullscreen && showGap ? 0 : 8;
    final double itemSpacing = showGap ? 10 : 0;

    if (preferences.pageFit == ReaderPageFit.fitScreen) {
      final double viewportHeight = screenSize.height * 0.72;
      return topPadding + (viewportHeight + itemSpacing) * imageIndex;
    }

    double offset = topPadding;
    final double maxReaderWidth = desktopReaderMaxWidth(
      context,
      preferences.pageFit,
    );
    final double contentWidth = maxReaderWidth.isFinite
        ? math.min(screenSize.width, maxReaderWidth)
        : screenSize.width;
    final Map<String, double> aspectRatios = _controller.imageAspectRatios;
    for (int index = 0; index < imageIndex; index += 1) {
      final String imageUrl = page.imageUrls[index];
      final double rawAspectRatio = aspectRatios[imageUrl] ?? 0.72;
      final double safeAspectRatio =
          rawAspectRatio.isFinite && rawAspectRatio > 0.05
          ? rawAspectRatio
          : 0.72;
      offset += (contentWidth / safeAspectRatio) + itemSpacing;
    }
    return offset;
  }

  Widget _buildChapterControlsOverlay(
    BuildContext context,
    ReaderPageData page,
  ) {
    final EdgeInsets viewPadding = MediaQuery.viewPaddingOf(context);
    final ReaderPreferences preferences = _controller.preferences;
    final double horizontalPadding = preferences.showPageGap ? 12 : 0;
    final double bottomPadding =
        (viewPadding.bottom > 0 ? viewPadding.bottom : 0) + 12;
    return Positioned(
      left: horizontalPadding,
      right: horizontalPadding,
      bottom: bottomPadding,
      child: IgnorePointer(
        ignoring: !_controller.isChapterControlsVisible,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          offset: _controller.isChapterControlsVisible
              ? Offset.zero
              : const Offset(0, 1.08),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            opacity: _controller.isChapterControlsVisible ? 1 : 0,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: usesDesktopLayout(context)
                      ? kDesktopReaderControlsMaxWidth
                      : double.infinity,
                ),
                child: _buildReaderChapterControls(context, page),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReaderScrollableContent(
    BuildContext context,
    ReaderPageData page,
  ) {
    final ReaderPreferences preferences = _controller.preferences;
    final bool showGap = preferences.showPageGap;
    final double topPadding = preferences.fullscreen && showGap ? 0 : 8;
    final bool showCommentTail = _controller.shouldShowCommentTailPage(page);
    final bool hasNextChapter = page.nextHref.trim().isNotEmpty;
    final ScrollPhysics scrollPhysics =
        (_controller.isScaleGestureActive || _controller.zoomScale > 1.01)
        ? const NeverScrollableScrollPhysics()
        : const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics());
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        _handleScrollLifecycle(notification);
        if (!_controller.isZoomGestureLocked) {
          _controller.handleChapterPull(
            notification,
            page: page,
            controller: _controller.scrollController,
          );
        }
        if (_isUserDrivenScrollNotification(notification)) {
          _controller.noteUserInteraction();
        }
        return false;
      },
      child: ListView.builder(
        key: ValueKey<String>(
          'reader-scroll-${page.uri}-${preferences.pageFit.name}-$showGap-$showCommentTail',
        ),
        controller: _controller.scrollController,
        physics: scrollPhysics,
        padding: EdgeInsets.only(top: topPadding, bottom: 16),
        itemCount:
            page.imageUrls.length + (showCommentTail || hasNextChapter ? 1 : 0),
        itemBuilder: (BuildContext context, int index) {
          if (index >= page.imageUrls.length) {
            return showCommentTail
                ? _buildReaderCommentTailPage(context, page)
                : _buildReaderNextChapterFooter(context, page);
          }
          return Padding(
            key: _controller.imageItemKeyFor(index),
            padding: EdgeInsets.only(bottom: showGap ? 10 : 0),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: desktopReaderMaxWidth(context, preferences.pageFit),
                ),
                child: _buildReaderImageFrame(
                  context,
                  page: page,
                  imageIndex: index,
                  imageUrl: page.imageUrls[index],
                  viewportHeight: preferences.pageFit == ReaderPageFit.fitScreen
                      ? MediaQuery.sizeOf(context).height * 0.72
                      : null,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildReaderPagedContent(BuildContext context, ReaderPageData page) {
    final ReaderPreferences preferences = _controller.preferences;
    final bool reverse =
        preferences.readingDirection == ReaderReadingDirection.rightToLeft;
    final double topPadding = preferences.fullscreen && preferences.showPageGap
        ? 0
        : 8;
    final bool showCommentTail = _controller.shouldShowCommentTailPage(page);
    final bool hasNextChapter = page.nextHref.trim().isNotEmpty;
    final bool instantPageSwitch = preferences.disablePageTransitionAnimation;
    final ScrollPhysics pagePhysics =
        _controller.isZoomGestureLocked || instantPageSwitch
        ? const NeverScrollableScrollPhysics()
        : const ReaderPagedScrollPhysics(
            triggerPageRatio: 0.65,
            parent: BouncingScrollPhysics(),
          );
    final Widget pageView = PageView.builder(
      key: ValueKey<String>(
        'reader-paged-${page.uri}-${preferences.readingDirection.name}-${preferences.pageFit.name}-${preferences.showPageGap}-$showCommentTail',
      ),
      controller: _controller.pageController,
      physics: pagePhysics,
      reverse: reverse,
      itemCount: _controller.readerPagedPageCount(page),
      onPageChanged: _controller.handlePageChanged,
      itemBuilder: (BuildContext context, int index) {
        final ScrollController scrollController = _controller
            .pagedScrollControllerFor(index);
        final bool isCommentPage = index >= page.imageUrls.length;
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Widget pageBody = isCommentPage
                ? _buildReaderCommentTailPage(
                    context,
                    page,
                    minHeight: constraints.maxHeight,
                  )
                : _buildReaderPagedPageBody(
                    context,
                    page: page,
                    imageIndex: index,
                    imageUrl: page.imageUrls[index],
                    constraints: constraints,
                    showNextChapterFooter:
                        !showCommentTail &&
                        hasNextChapter &&
                        index == page.imageUrls.length - 1,
                  );
            final Widget wrappedBody = isCommentPage
                ? pageBody
                : NotificationListener<ScrollNotification>(
                    onNotification: (ScrollNotification notification) {
                      _handleScrollLifecycle(notification);
                      if (_isUserDrivenScrollNotification(notification)) {
                        _controller.noteUserInteraction();
                      }
                      return false;
                    },
                    child: SingleChildScrollView(
                      controller: scrollController,
                      physics: _controller.isZoomGestureLocked
                          ? const NeverScrollableScrollPhysics()
                          : const BouncingScrollPhysics(),
                      child: pageBody,
                    ),
                  );
            return Padding(
              padding: preferences.showPageGap
                  ? EdgeInsets.only(top: topPadding, bottom: 8)
                  : EdgeInsets.zero,
              child: wrappedBody,
            );
          },
        );
      },
    );
    final Widget pagedContent = instantPageSwitch
        ? GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) => _instantPageDragDx = 0,
            onHorizontalDragUpdate: (DragUpdateDetails details) {
              _instantPageDragDx += details.primaryDelta ?? 0;
            },
            onHorizontalDragEnd: (DragEndDetails details) =>
                _handleInstantPageSwipe(details, reverse: reverse),
            onHorizontalDragCancel: () => _instantPageDragDx = 0,
            child: pageView,
          )
        : pageView;
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        _handleScrollLifecycle(notification);
        final int pageCount = _controller.readerPagedPageCount(page);
        final bool isLastReaderPage =
            _controller.currentPageIndex >= pageCount - 1;
        final bool isFirstReaderPage = _controller.currentPageIndex <= 0;
        final bool hasPreviousChapter = page.prevHref.trim().isNotEmpty;
        if (!_controller.isZoomGestureLocked &&
            ((isLastReaderPage && hasNextChapter) ||
                (isFirstReaderPage && hasPreviousChapter))) {
          _controller.handleChapterPull(
            notification,
            page: page,
            controller: _controller.pageController,
            axis: Axis.horizontal,
          );
        }
        if (_isUserDrivenScrollNotification(notification)) {
          _controller.noteUserInteraction();
        }
        return false;
      },
      child: pagedContent,
    );
  }

  void _handleInstantPageSwipe(
    DragEndDetails details, {
    required bool reverse,
  }) {
    final double dragDx = _instantPageDragDx;
    _instantPageDragDx = 0;
    if (_controller.isZoomGestureLocked) {
      return;
    }
    final double velocity = details.primaryVelocity ?? 0;
    final bool isFling = velocity.abs() >= _instantPageSwipeVelocity;
    final bool isDrag = dragDx.abs() >= _instantPageSwipeDistance;
    final double direction = isFling ? velocity : dragDx;
    if (!isFling && !isDrag) {
      return;
    }
    final bool forward = reverse ? direction > 0 : direction < 0;
    if (forward) {
      unawaited(_controller.stepForward());
    } else {
      unawaited(_controller.stepBackward());
    }
  }

  Widget _buildReaderImageFrame(
    BuildContext context, {
    required ReaderPageData page,
    required int imageIndex,
    required String imageUrl,
    double? viewportHeight,
  }) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final ReaderPreferences preferences = _controller.preferences;
    final bool showGap = preferences.showPageGap;
    final BoxFit fit = preferences.pageFit == ReaderPageFit.fitWidth
        ? BoxFit.fitWidth
        : BoxFit.contain;
    final Uri? parsedUri = Uri.tryParse(imageUrl);
    final bool isLocalFile = parsedUri != null && parsedUri.scheme == 'file';
    final bool isDocumentTreeFile =
        parsedUri != null && parsedUri.scheme == 'content';
    final bool isDocumentTreeRelativeFile =
        parsedUri != null && parsedUri.scheme == treeImageScheme;
    final ImageProvider<Object> imageProvider;
    if (isLocalFile) {
      imageProvider = FileImage(File.fromUri(parsedUri));
    } else if (isDocumentTreeRelativeFile) {
      imageProvider = TreeImageProvider.fromUri(parsedUri);
    } else if (isDocumentTreeFile) {
      imageProvider = DocumentTreeImageProvider(imageUrl);
    } else {
      imageProvider = CachedNetworkImageProvider(
        imageUrl,
        cacheManager: AppImageCaches.readerCache,
        headers: AppImageCaches.readerImageHeaders(page.uri),
      );
    }
    return ColoredBox(
      color: showGap ? colorScheme.surface : colorScheme.surfaceContainerLowest,
      child: ReaderChapterImage(
        key: ValueKey<String>('reader-image-$imageUrl-$viewportHeight'),
        imageProvider: imageProvider,
        debugUrl: imageUrl,
        fit: fit,
        viewportHeight: viewportHeight,
        aspectRatio: _controller.imageAspectRatios[imageUrl],
        onResolvedAspectRatio: (double aspectRatio) {
          if (!aspectRatio.isFinite || aspectRatio <= 0) return;
          _controller.recordImageAspectRatio(imageUrl, aspectRatio);
        },
      ),
    );
  }

  Widget _buildReaderPagedPageBody(
    BuildContext context, {
    required ReaderPageData page,
    required int imageIndex,
    required String imageUrl,
    required BoxConstraints constraints,
    required bool showNextChapterFooter,
  }) {
    final ReaderPreferences preferences = _controller.preferences;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: constraints.maxHeight),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: desktopReaderMaxWidth(context, preferences.pageFit),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _buildReaderImageFrame(
                context,
                page: page,
                imageIndex: imageIndex,
                imageUrl: imageUrl,
                viewportHeight: preferences.pageFit == ReaderPageFit.fitScreen
                    ? constraints.maxHeight
                    : null,
              ),
              if (showNextChapterFooter)
                _buildReaderNextChapterFooter(context, page),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReaderCommentTailPage(
    BuildContext context,
    ReaderPageData page, {
    double minHeight = 0,
  }) {
    final List<ChapterComment> comments =
        _controller.commentsChapterId == readerChapterIdForPage(page)
        ? _controller.chapterComments
        : const <ChapterComment>[];
    final Size screenSize = MediaQuery.sizeOf(context);
    final bool isPagedCommentPage = minHeight > 0;
    final double panelMaxHeight = isPagedCommentPage
        ? minHeight
        : screenSize.height;
    final double commentCloudMaxHeight = panelMaxHeight > 188
        ? panelMaxHeight - 108
        : 80;
    final Widget commentSection = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: commentCloudMaxHeight),
          child: _buildReaderCommentCloud(context, page, comments: comments),
        ),
        const SizedBox(height: 6),
        _buildReaderCommentComposer(context, page),
      ],
    );
    if (isPagedCommentPage) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: SizedBox(
          height: minHeight,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const SizedBox(height: 12),
              Flexible(child: commentSection),
              const SizedBox(height: 16),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: screenSize.height),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SizedBox(height: 12),
            commentSection,
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  bool _isUserDrivenScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    return switch (notification) {
      ScrollStartNotification(:final DragStartDetails? dragDetails) =>
        dragDetails != null,
      ScrollUpdateNotification(:final DragUpdateDetails? dragDetails) =>
        dragDetails != null,
      OverscrollNotification(:final DragUpdateDetails? dragDetails) =>
        dragDetails != null,
      _ => false,
    };
  }

  void _handleScrollLifecycle(ScrollNotification notification) {
    if (notification.depth != 0) return;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _controller.cancelAutoTurn();
      return;
    }
    if (notification is ScrollEndNotification &&
        notification.dragDetails != null) {
      _controller.restartAutoTurnAfterScroll();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? _) {
        final ReaderPageData page = widget.page;
        final ColorScheme colorScheme = Theme.of(context).colorScheme;
        final ReaderPreferences preferences = _controller.preferences;
        final bool isZoomed = _controller.zoomScale > 1.01;

        Widget readerContent = preferences.isPaged
            ? _buildReaderPagedContent(context, page)
            : _buildReaderScrollableContent(context, page);

        readerContent = ClipRect(
          child: Transform.translate(
            offset: isZoomed
                ? Offset(_controller.panOffsetX, _controller.panOffsetY)
                : Offset.zero,
            child: Transform.scale(
              scale: _controller.zoomScale,
              alignment: Alignment.center,
              child: readerContent,
            ),
          ),
        );

        if (isZoomed) {
          final Size screenSize = MediaQuery.sizeOf(context);
          final double maxPanX =
              screenSize.width * (_controller.zoomScale - 1) / 2;
          final double maxPanY =
              screenSize.height * (_controller.zoomScale - 1) / 2;
          readerContent = GestureDetector(
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onPanUpdate: (DragUpdateDetails details) {
              if (_controller.isScaleGestureActive) return;
              final double dy = details.delta.dy;
              final double proposedPanY = _controller.panOffsetY + dy;
              final double clampedPanY = proposedPanY.clamp(-maxPanY, maxPanY);
              final double consumedDy = clampedPanY - _controller.panOffsetY;
              final double remainingDy = dy - consumedDy;
              double overscrollDy = 0;
              if (remainingDy.abs() > 0.5) {
                final ScrollController vc = _controller.preferences.isPaged
                    ? _controller.pagedScrollControllerFor(
                        _controller.currentPageIndex,
                      )
                    : _controller.scrollController;
                if (vc.hasClients) {
                  final double oldOffset = vc.offset;
                  final double rawOffset =
                      oldOffset - remainingDy / _controller.zoomScale;
                  final double newOffset = rawOffset.clamp(
                    vc.position.minScrollExtent,
                    vc.position.maxScrollExtent,
                  );
                  vc.jumpTo(newOffset);
                  final double scrolledScreen =
                      (oldOffset - newOffset) * _controller.zoomScale;
                  overscrollDy = remainingDy - scrolledScreen;
                } else {
                  overscrollDy = remainingDy;
                }
              }
              if (overscrollDy.abs() > 0.5) {
                _controller.handleZoomedOverscroll(page, overscrollDy);
              }
              _controller.updatePanOffset(
                x: (_controller.panOffsetX + details.delta.dx).clamp(
                  -maxPanX,
                  maxPanX,
                ),
                y: clampedPanY,
              );
            },
            onPanEnd: (DragEndDetails details) {
              if (_controller.isScaleGestureActive) return;
              _controller.handleZoomedPanEnd(page);
              final ScrollController vc = _controller.preferences.isPaged
                  ? _controller.pagedScrollControllerFor(
                      _controller.currentPageIndex,
                    )
                  : _controller.scrollController;
              if (vc.hasClients) {
                final double vy = details.velocity.pixelsPerSecond.dy;
                if (vy.abs() > 100) {
                  final double targetOffset =
                      (vc.offset - vy * 0.25 / _controller.zoomScale).clamp(
                        vc.position.minScrollExtent,
                        vc.position.maxScrollExtent,
                      );
                  unawaited(
                    vc.animateTo(
                      targetOffset,
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutCubic,
                    ),
                  );
                }
              }
            },
            child: readerContent,
          );
        } else {
          readerContent = GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapUp: _controller.isZoomGestureLocked
                ? null
                : _handleReaderTapUp,
            child: readerContent,
          );
        }

        return AnimatedOpacity(
          opacity: widget.isExitTransitionActive ? 0 : 1,
          duration: _readerExitFadeDuration,
          curve: Curves.easeOutCubic,
          child: IgnorePointer(
            ignoring: widget.isExitTransitionActive,
            child: Scaffold(
              backgroundColor: colorScheme.surfaceContainerLowest,
              body: SizedBox(
                key: _controller.viewportKey,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Positioned.fill(
                      child: ReaderPinchZoomDetector(
                        onPinchStart: _controller.handlePinchZoomStart,
                        onPinchUpdate: _controller.handlePinchZoomUpdate,
                        onPinchEnd: _controller.handlePinchZoomEnd,
                        child: readerContent,
                      ),
                    ),
                    _buildReaderOverlay(context, page),
                    _buildChapterControlsOverlay(context, page),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ReaderClockLabel extends StatefulWidget {
  const _ReaderClockLabel();

  @override
  State<_ReaderClockLabel> createState() => _ReaderClockLabelState();
}

class _ReaderClockLabelState extends State<_ReaderClockLabel> {
  Timer? _timer;
  late String _label;

  @override
  void initState() {
    super.initState();
    _label = _formatNow();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _label = _formatNow();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static String _formatNow() {
    final DateTime now = DateTime.now();
    final String hour = now.hour.toString().padLeft(2, '0');
    final String minute = now.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return ReaderStatusLabel(label: _label, fontSize: 14);
  }
}
