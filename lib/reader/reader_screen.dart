import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_copy/models/app_preferences.dart';
import 'package:easy_copy/models/chapter_comment.dart';
import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/reader/internal/reader_comment_layout.dart';
import 'package:easy_copy/reader/internal/reader_paged_scroll_physics.dart';
import 'package:easy_copy/reader/reader_controller.dart';
import 'package:easy_copy/reader/reader_image.dart';
import 'package:easy_copy/reader/reader_pinch_zoom.dart';
import 'package:easy_copy/reader/reader_progress_seek_bar.dart';
import 'package:easy_copy/reader/reader_sheet_swipe_dismiss.dart';
import 'package:easy_copy/reader/reader_status_label.dart';
import 'package:easy_copy/services/app_preferences_controller.dart';
import 'package:easy_copy/services/document_tree_image_provider.dart';
import 'package:easy_copy/services/document_tree_relative_image_provider.dart';
import 'package:easy_copy/services/image_cache.dart';
import 'package:easy_copy/services/local_library_store.dart';
import 'package:easy_copy/services/reader_comment_utils.dart';
import 'package:easy_copy/services/reader_history_recorder.dart';
import 'package:easy_copy/services/reader_platform_bridge.dart';
import 'package:easy_copy/services/reader_progress_store.dart';
import 'package:easy_copy/services/site_api_client.dart';
import 'package:easy_copy/services/site_session.dart';
import 'package:easy_copy/widgets/settings_ui.dart';
import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';

const Duration _readerExitFadeDuration = Duration(milliseconds: 220);
const double _readerUiToggleHorizontalInsetRatio = 0.075;
const double _readerSettingsSwipeDismissDistance = 72;

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    required this.page,
    required this.isExitTransitionActive,
    required this.onRequestChapterNavigation,
    required this.onRequestAuth,
    required this.onLogoutForExpiredSession,
    required this.onResolveHistoryCover,
    super.key,
  });

  final ReaderPageData page;
  final bool isExitTransitionActive;
  final ReaderChapterNavigationCallback onRequestChapterNavigation;
  final Future<void> Function() onRequestAuth;
  final Future<void> Function() onLogoutForExpiredSession;
  final ResolveReaderHistoryCover onResolveHistoryCover;

  @override
  State<ReaderScreen> createState() => ReaderScreenState();
}

class ReaderScreenState extends State<ReaderScreen> {
  late final ReaderController _controller;

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
      onShowMessage: _showSnackBar,
    );
    _controller.attachPlatformSubscriptions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.setPage(widget.page);
    });
  }

  @override
  void didUpdateWidget(covariant ReaderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.page.uri != widget.page.uri ||
        !identical(oldWidget.page, widget.page)) {
      _controller.setPage(widget.page, previousUri: oldWidget.page.uri);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    unawaited(_controller.restoreDefaultEnvironment());
    super.dispose();
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
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
    final double uiToggleInsetWidth =
        viewportWidth * _readerUiToggleHorizontalInsetRatio;
    final double dx = details.localPosition.dx;
    if (dx <= uiToggleInsetWidth || dx >= viewportWidth - uiToggleInsetWidth) {
      return;
    }
    if (details.localPosition.dy <= viewportHeight * 0.5) {
      _controller.hideChapterControls();
      unawaited(_showReaderSettingsSheet());
      return;
    }
    _controller.toggleChapterControls();
  }

  Future<void> _showReaderSettingsSheet() async {
    if (_controller.isSettingsOpen) return;
    _controller.setSettingsSheetOpen(true);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      showDragHandle: true,
      builder: _buildReaderSettingsSheet,
    );
    _controller.setSettingsSheetOpen(false);
  }

  Widget _buildReaderSettingsSheet(BuildContext context) {
    final double maxHeight = MediaQuery.sizeOf(context).height * 0.78;
    final AppPreferencesController preferencesController =
        _controller.preferencesController;
    return AnimatedBuilder(
      animation: preferencesController,
      builder: (BuildContext context, Widget? _) {
        final ReaderPreferences preferences = _controller.preferences;
        return ReaderSheetSwipeDismissRegion(
          dismissDistance: _readerSettingsSwipeDismissDistance,
          onDismiss: () => Navigator.of(context).maybePop(),
          child: SafeArea(
            child: SizedBox(
              key: const ValueKey<String>('reader-settings-sheet'),
              height: maxHeight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  children: <Widget>[
                    Expanded(
                      child: ListView(
                        children: <Widget>[
                          SettingsSection(
                            children: <Widget>[
                              SettingsSelectRow<ReaderScreenOrientation>(
                                label: '屏幕方向',
                                value: preferences.screenOrientation,
                                items: ReaderScreenOrientation.values
                                    .map((ReaderScreenOrientation value) {
                                      return DropdownMenuItem<
                                        ReaderScreenOrientation
                                      >(
                                        value: value,
                                        child: Text(
                                          value ==
                                                  ReaderScreenOrientation
                                                      .portrait
                                              ? '竖屏'
                                              : '横屏',
                                        ),
                                      );
                                    })
                                    .toList(growable: false),
                                onChanged: (ReaderScreenOrientation? value) {
                                  if (value == null) return;
                                  unawaited(
                                    preferencesController
                                        .updateReaderPreferences(
                                          (ReaderPreferences current) =>
                                              current.copyWith(
                                                screenOrientation: value,
                                              ),
                                        ),
                                  );
                                },
                              ),
                              SettingsSelectRow<ReaderReadingDirection>(
                                label: '阅读方向',
                                value: preferences.readingDirection,
                                items: ReaderReadingDirection.values
                                    .map((ReaderReadingDirection value) {
                                      return DropdownMenuItem<
                                        ReaderReadingDirection
                                      >(
                                        value: value,
                                        child: Text(switch (value) {
                                          ReaderReadingDirection.topToBottom =>
                                            '从上到下',
                                          ReaderReadingDirection.leftToRight =>
                                            '从左到右',
                                          ReaderReadingDirection.rightToLeft =>
                                            '从右到左',
                                        }),
                                      );
                                    })
                                    .toList(growable: false),
                                onChanged: (ReaderReadingDirection? value) {
                                  if (value == null) return;
                                  unawaited(
                                    preferencesController
                                        .updateReaderPreferences(
                                          (ReaderPreferences current) =>
                                              current.copyWith(
                                                readingDirection: value,
                                              ),
                                        ),
                                  );
                                },
                              ),
                              SettingsSelectRow<ReaderPageFit>(
                                label: '页面缩放',
                                value: preferences.pageFit,
                                items: ReaderPageFit.values
                                    .map((ReaderPageFit value) {
                                      return DropdownMenuItem<ReaderPageFit>(
                                        value: value,
                                        child: Text(
                                          value == ReaderPageFit.fitWidth
                                              ? '匹配宽度'
                                              : '适应屏幕',
                                        ),
                                      );
                                    })
                                    .toList(growable: false),
                                onChanged: (ReaderPageFit? value) {
                                  if (value == null) return;
                                  unawaited(
                                    preferencesController
                                        .updateReaderPreferences(
                                          (ReaderPreferences current) =>
                                              current.copyWith(pageFit: value),
                                        ),
                                  );
                                },
                              ),
                              SettingsSelectRow<ReaderOpeningPosition>(
                                label: '开页位置',
                                value: preferences.openingPosition,
                                items: ReaderOpeningPosition.values
                                    .map((ReaderOpeningPosition value) {
                                      return DropdownMenuItem<
                                        ReaderOpeningPosition
                                      >(
                                        value: value,
                                        child: Text(
                                          value == ReaderOpeningPosition.top
                                              ? '顶部'
                                              : '中心',
                                        ),
                                      );
                                    })
                                    .toList(growable: false),
                                onChanged: (ReaderOpeningPosition? value) {
                                  if (value == null) return;
                                  unawaited(
                                    preferencesController
                                        .updateReaderPreferences(
                                          (ReaderPreferences current) => current
                                              .copyWith(openingPosition: value),
                                        ),
                                  );
                                },
                              ),
                              SettingsSliderRow(
                                label:
                                    '自动翻页(${preferences.autoPageTurnSeconds}秒)',
                                value: preferences.autoPageTurnSeconds
                                    .toDouble(),
                                max: 10,
                                divisions: 10,
                                onChanged: (double value) {
                                  unawaited(
                                    preferencesController
                                        .updateReaderPreferences(
                                          (ReaderPreferences current) =>
                                              current.copyWith(
                                                autoPageTurnSeconds: value
                                                    .round(),
                                              ),
                                        ),
                                  );
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SettingsSection(
                            children: <Widget>[
                              SettingsSwitchRow(
                                label: '显示评论页',
                                value: preferences.showChapterComments,
                                onChanged: (bool value) {
                                  unawaited(
                                    preferencesController
                                        .updateReaderPreferences(
                                          (ReaderPreferences current) =>
                                              current.copyWith(
                                                showChapterComments: value,
                                              ),
                                        ),
                                  );
                                },
                              ),
                              SettingsSwitchRow(
                                label: '屏幕常亮',
                                value: preferences.keepScreenOn,
                                onChanged: (bool value) {
                                  unawaited(
                                    preferencesController
                                        .updateReaderPreferences(
                                          (ReaderPreferences current) => current
                                              .copyWith(keepScreenOn: value),
                                        ),
                                  );
                                },
                              ),
                              SettingsSwitchRow(
                                label: '显示时钟',
                                value: preferences.showClock,
                                onChanged: (bool value) {
                                  unawaited(
                                    preferencesController
                                        .updateReaderPreferences(
                                          (ReaderPreferences current) => current
                                              .copyWith(showClock: value),
                                        ),
                                  );
                                },
                              ),
                              SettingsSwitchRow(
                                label: '显示进度',
                                value: preferences.showProgress,
                                onChanged: (bool value) {
                                  unawaited(
                                    preferencesController
                                        .updateReaderPreferences(
                                          (ReaderPreferences current) => current
                                              .copyWith(showProgress: value),
                                        ),
                                  );
                                },
                              ),
                              if (_controller.platformBridge.isAndroidSupported)
                                SettingsSwitchRow(
                                  label: '显示电量',
                                  value: preferences.showBattery,
                                  onChanged: (bool value) {
                                    unawaited(
                                      preferencesController
                                          .updateReaderPreferences(
                                            (ReaderPreferences current) =>
                                                current.copyWith(
                                                  showBattery: value,
                                                ),
                                          ),
                                    );
                                  },
                                ),
                              SettingsSwitchRow(
                                label: '显示页面间隔',
                                value: preferences.showPageGap,
                                onChanged: (bool value) {
                                  unawaited(
                                    preferencesController
                                        .updateReaderPreferences(
                                          (ReaderPreferences current) => current
                                              .copyWith(showPageGap: value),
                                        ),
                                  );
                                },
                              ),
                              if (_controller.platformBridge.isAndroidSupported)
                                SettingsSwitchRow(
                                  label: '使用音量键翻页',
                                  value: preferences.useVolumeKeysForPaging,
                                  onChanged: (bool value) {
                                    unawaited(
                                      preferencesController
                                          .updateReaderPreferences(
                                            (ReaderPreferences current) =>
                                                current.copyWith(
                                                  useVolumeKeysForPaging: value,
                                                ),
                                          ),
                                    );
                                  },
                                ),
                              SettingsSwitchRow(
                                label: '全屏',
                                value: preferences.fullscreen,
                                onChanged: (bool value) {
                                  unawaited(
                                    preferencesController
                                        .updateReaderPreferences(
                                          (ReaderPreferences current) => current
                                              .copyWith(fullscreen: value),
                                        ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
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
              child: ReaderStatusLabel(
                label: _readerClockLabel(),
                fontSize: 14,
              ),
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
            _buildReaderNextChapterCueOverlay(context, page),
        ],
      ),
    );
  }

  String _readerClockLabel() {
    final DateTime now = DateTime.now();
    final String hour = now.hour.toString().padLeft(2, '0');
    final String minute = now.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
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
    );
  }

  void _seekReaderToImageIndex(
    BuildContext context,
    ReaderPageData page,
    int imageIndex,
  ) {
    if (_controller.isZoomGestureLocked || page.imageUrls.isEmpty) return;
    final int clampedIndex = imageIndex.clamp(0, page.imageUrls.length - 1);
    final double estimatedOffset = _estimateReaderScrollOffsetForImageIndex(
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

  double _estimateReaderScrollOffsetForImageIndex(
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
    final double contentWidth = screenSize.width;
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

  Widget _buildReaderChapterControlsOverlay(
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
            child: _buildReaderChapterControls(context, page),
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
        if (!_controller.isZoomGestureLocked) {
          _controller.handleChapterPullScrollNotification(
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
            child: _buildReaderImageFrame(
              context,
              page: page,
              imageIndex: index,
              imageUrl: page.imageUrls[index],
              viewportHeight: preferences.pageFit == ReaderPageFit.fitScreen
                  ? MediaQuery.sizeOf(context).height * 0.72
                  : null,
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
    final ScrollPhysics pagePhysics = _controller.isZoomGestureLocked
        ? const NeverScrollableScrollPhysics()
        : const ReaderPagedScrollPhysics(
            triggerPageRatio: 0.65,
            parent: BouncingScrollPhysics(),
          );
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        final bool isLastReaderPage =
            _controller.currentPageIndex >=
            _controller.readerPagedPageCount(page) - 1;
        if (!_controller.isZoomGestureLocked &&
            isLastReaderPage &&
            hasNextChapter) {
          _controller.handleChapterPullScrollNotification(
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
      child: PageView.builder(
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
      ),
    );
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
        parsedUri != null &&
        parsedUri.scheme == documentTreeRelativeImageScheme;
    final ImageProvider<Object> imageProvider;
    if (isLocalFile) {
      imageProvider = FileImage(File.fromUri(parsedUri));
    } else if (isDocumentTreeRelativeFile) {
      imageProvider = DocumentTreeRelativeImageProvider.fromUri(parsedUri);
    } else if (isDocumentTreeFile) {
      imageProvider = DocumentTreeImageProvider(imageUrl);
    } else {
      imageProvider = CachedNetworkImageProvider(
        imageUrl,
        cacheManager: EasyCopyImageCaches.readerCache,
        headers: EasyCopyImageCaches.readerImageHeaders(page.uri),
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
        child: SizedBox(
          width: double.infinity,
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
            children: <Widget>[
              const SizedBox(height: 12),
              commentSection,
              const Spacer(),
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

  Widget _buildReaderCommentComposer(
    BuildContext context,
    ReaderPageData page,
  ) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final SiteSession session = _controller.session;
    final bool isAuthenticated =
        session.isAuthenticated && (session.token ?? '').isNotEmpty;
    final Widget actionButton = isAuthenticated
        ? FilledButton(
            onPressed: _controller.isCommentSubmitting
                ? null
                : () => unawaited(_controller.submitComment(page)),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(_controller.isCommentSubmitting ? '发送中' : '发送'),
          )
        : TextButton(
            onPressed: () => unawaited(widget.onRequestAuth()),
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('登录'),
          );
    return Stack(
      alignment: Alignment.bottomRight,
      children: <Widget>[
        TextField(
          controller: _controller.commentController,
          enabled: !_controller.isCommentSubmitting,
          readOnly: !isAuthenticated,
          onTap: !isAuthenticated
              ? () => unawaited(widget.onRequestAuth())
              : null,
          maxLines: 3,
          minLines: 2,
          textInputAction: TextInputAction.newline,
          decoration: InputDecoration(
            hintText: isAuthenticated ? '说点什么...' : '登录后评论',
            filled: true,
            fillColor: colorScheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: colorScheme.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: colorScheme.outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide(color: colorScheme.primary, width: 1.2),
            ),
            contentPadding: const EdgeInsets.fromLTRB(12, 10, 90, 12),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 8),
          child: actionButton,
        ),
      ],
    );
  }

  void _handleReaderCommentCloudDragUpdate(DragUpdateDetails details) {
    final double? primaryDelta = details.primaryDelta;
    if (primaryDelta == null ||
        !_controller.commentScrollController.hasClients) {
      return;
    }
    final ScrollPosition position =
        _controller.commentScrollController.position;
    final double nextOffset = (position.pixels - primaryDelta)
        .clamp(0.0, position.maxScrollExtent)
        .toDouble();
    if ((nextOffset - position.pixels).abs() < 0.5) return;
    _controller.commentScrollController.jumpTo(nextOffset);
  }

  void _handleReaderCommentCloudDragEnd(DragEndDetails details) {
    if (!_controller.commentScrollController.hasClients) return;
    final double velocity = -(details.primaryVelocity ?? 0);
    if (velocity.abs() < 90) return;
    final ScrollPosition position =
        _controller.commentScrollController.position;
    if (position.maxScrollExtent <= 0) return;
    final double targetOffset = (position.pixels + (velocity * 0.18))
        .clamp(0.0, position.maxScrollExtent)
        .toDouble();
    if ((targetOffset - position.pixels).abs() < 1) return;
    unawaited(
      _controller.commentScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  Widget _buildReaderCommentScrollStrip({required bool enabled}) {
    if (!enabled) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.center,
      child: FractionallySizedBox(
        widthFactor: 0.3,
        heightFactor: 1,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragUpdate: _handleReaderCommentCloudDragUpdate,
          onVerticalDragEnd: _handleReaderCommentCloudDragEnd,
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  Widget _buildReaderCommentCloud(
    BuildContext context,
    ReaderPageData page, {
    required List<ChapterComment> comments,
  }) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    if (_controller.isCommentsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_controller.commentsError.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              _controller.commentsError,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.78),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => unawaited(_controller.loadComments(page)),
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (comments.isEmpty) {
      return Center(
        child: Text(
          '暂无评论',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colorScheme.onSurface.withValues(alpha: 0.72),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    final List<ReaderCommentCluster> clusters = buildReaderCommentClusters(
      comments,
    );
    if (clusters.isEmpty) {
      return Center(
        child: Text(
          '暂无评论',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colorScheme.onSurface.withValues(alpha: 0.72),
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final ReaderCommentCloudLayout layout = _buildReaderCommentCloudLayout(
          context,
          clusters,
          maxWidth: constraints.maxWidth,
        );
        final double contentHeight = layout.height + 8;
        final double maxViewportHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : contentHeight;
        final double viewportHeight = math.min(
          contentHeight,
          maxViewportHeight,
        );
        final bool canScroll = contentHeight > viewportHeight + 0.5;
        final Widget cloud = Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: SizedBox(
            width: constraints.maxWidth,
            height: layout.height,
            child: Stack(
              clipBehavior: Clip.none,
              children: layout.placements
                  .map(
                    (ReaderCommentBubblePlacement placement) => Positioned(
                      left: placement.left,
                      top: placement.top,
                      child: _buildReaderCommentBubble(
                        context,
                        clusters[placement.index],
                        index: placement.index,
                        width: placement.width,
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        );
        return SizedBox(
          height: viewportHeight,
          child: ClipRect(
            child: Stack(
              children: <Widget>[
                IgnorePointer(
                  ignoring: true,
                  child: SingleChildScrollView(
                    controller: _controller.commentScrollController,
                    physics: const NeverScrollableScrollPhysics(),
                    child: cloud,
                  ),
                ),
                _buildReaderCommentScrollStrip(enabled: canScroll),
              ],
            ),
          ),
        );
      },
    );
  }

  ReaderCommentCloudLayout _buildReaderCommentCloudLayout(
    BuildContext context,
    List<ReaderCommentCluster> clusters, {
    required double maxWidth,
  }) {
    final double availableWidth = maxWidth
        .clamp(120.0, double.infinity)
        .toDouble();
    const double slotWidth = 6;
    const double runSpacing = 6;
    final double maxBubbleWidth = availableWidth >= 420
        ? availableWidth * 0.72
        : availableWidth * 0.92;
    final double minBubbleWidth = math.min(
      maxBubbleWidth,
      availableWidth >= 420 ? 72 : 56,
    );
    final int slotCount = math.max(1, (availableWidth / slotWidth).floor());
    final List<double> skyline = List<double>.filled(slotCount, 0);
    final List<ReaderCommentBubblePlacement> placements =
        <ReaderCommentBubblePlacement>[];
    for (int index = 0; index < clusters.length; index++) {
      final ReaderCommentBubbleMetrics metrics = _measureReaderCommentBubble(
        context,
        clusters[index],
        minBubbleWidth: minBubbleWidth,
        maxBubbleWidth: maxBubbleWidth,
      );
      final int span = math.max(
        1,
        math.min(slotCount, (metrics.width / slotWidth).ceil()),
      );
      int bestStart = 0;
      double bestTop = double.infinity;
      for (int start = 0; start <= slotCount - span; start++) {
        double top = 0;
        for (int offset = 0; offset < span; offset++) {
          top = math.max(top, skyline[start + offset]);
        }
        if (top < bestTop - 0.5 ||
            ((top - bestTop).abs() < 0.5 && start < bestStart)) {
          bestTop = top;
          bestStart = start;
        }
      }
      final double left = bestStart * slotWidth;
      placements.add(
        ReaderCommentBubblePlacement(
          index: index,
          left: left,
          top: bestTop,
          width: metrics.width,
        ),
      );
      final double nextHeight = bestTop + metrics.height + runSpacing;
      for (int offset = 0; offset < span; offset++) {
        skyline[bestStart + offset] = nextHeight;
      }
    }
    final double contentHeight = placements.isEmpty
        ? 0
        : math.max(0, skyline.reduce(math.max) - runSpacing).toDouble();
    return ReaderCommentCloudLayout(
      height: contentHeight,
      placements: placements,
    );
  }

  ReaderCommentBubbleMetrics _measureReaderCommentBubble(
    BuildContext context,
    ReaderCommentCluster cluster, {
    required double minBubbleWidth,
    required double maxBubbleWidth,
  }) {
    const double horizontalPadding = 12;
    const double verticalPadding = 10;
    const double avatarGap = 5;
    final double avatarWidth = _readerCommentAvatarStackWidth(cluster.count);
    final TextScaler textScaler = MediaQuery.textScalerOf(context);
    final InlineSpan textSpan = TextSpan(
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        height: 1.25,
      ),
      text: cluster.message,
    );
    final TextPainter naturalPainter = TextPainter(
      text: textSpan,
      textDirection: Directionality.of(context),
      textScaler: textScaler,
    )..layout();
    final double bubbleWidth =
        (naturalPainter.width + horizontalPadding + avatarWidth + avatarGap)
            .clamp(minBubbleWidth, maxBubbleWidth)
            .toDouble();
    final TextPainter painter =
        TextPainter(
          text: textSpan,
          textDirection: Directionality.of(context),
          textScaler: textScaler,
        )..layout(
          maxWidth: math.max(
            18,
            bubbleWidth - horizontalPadding - avatarWidth - avatarGap,
          ),
        );
    final double contentHeight = math.max(22, painter.height);
    return ReaderCommentBubbleMetrics(
      width: bubbleWidth,
      height: contentHeight + verticalPadding,
    );
  }

  Widget _buildReaderCommentBubble(
    BuildContext context,
    ReaderCommentCluster cluster, {
    required int index,
    required double width,
  }) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final List<Color> bubbleColors = <Color>[
      colorScheme.secondaryContainer.withValues(alpha: 0.96),
      colorScheme.tertiaryContainer.withValues(alpha: 0.96),
      colorScheme.primaryContainer.withValues(alpha: 0.94),
      colorScheme.surfaceContainerHigh.withValues(alpha: 0.98),
    ];
    final Color backgroundColor = bubbleColors[index % bubbleColors.length];
    final Color foregroundColor =
        ThemeData.estimateBrightnessForColor(backgroundColor) == Brightness.dark
        ? Colors.white
        : colorScheme.onSurface;
    final TextStyle messageStyle = TextStyle(
      color: foregroundColor,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      height: 1.25,
    );
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: foregroundColor.withValues(alpha: 0.06)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildReaderCommentAvatarStack(cluster, foregroundColor),
              const SizedBox(width: 5),
              Flexible(
                child: RichText(
                  textScaler: MediaQuery.textScalerOf(context),
                  text: TextSpan(style: messageStyle, text: cluster.message),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _readerCommentAvatarStackWidth(int count) {
    const double avatarSize = 22;
    const double overlap = 8;
    final int visibleCount = math.max(1, math.min(3, count));
    return avatarSize + (visibleCount - 1) * (avatarSize - overlap);
  }

  Widget _buildReaderCommentAvatarStack(
    ReaderCommentCluster cluster,
    Color foregroundColor,
  ) {
    const double avatarSize = 22;
    const double overlap = 8;
    final int visibleCount = math.max(1, math.min(3, cluster.count));
    final double step = avatarSize - overlap;
    return SizedBox(
      width: _readerCommentAvatarStackWidth(cluster.count),
      height: avatarSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: List<Widget>.generate(visibleCount, (int index) {
          final bool isOverflowAvatar =
              cluster.hasOverflowAvatars && index == visibleCount - 1;
          final String avatarUrl = index < cluster.avatarUrls.length
              ? cluster.avatarUrls[index]
              : '';
          return Positioned(
            left: index * step,
            top: 0,
            child: SizedBox(
              width: avatarSize,
              height: avatarSize,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: foregroundColor.withValues(alpha: 0.18),
                    width: 1,
                  ),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    _buildReaderCommentAvatar(avatarUrl),
                    if (isOverflowAvatar)
                      ClipOval(
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: 0.54),
                          child: const Center(
                            child: Text(
                              '...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w900,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildReaderCommentAvatar(String avatarUrl) {
    if (avatarUrl.trim().isEmpty) {
      return const CircleAvatar(
        radius: 11,
        child: Icon(Icons.person_rounded, size: 13),
      );
    }
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: avatarUrl,
        width: 22,
        height: 22,
        fit: BoxFit.cover,
        cacheManager: EasyCopyImageCaches.readerCache,
        errorWidget: (BuildContext context, String url, Object error) {
          return const CircleAvatar(
            radius: 11,
            child: Icon(Icons.person_rounded, size: 13),
          );
        },
      ),
    );
  }

  Widget _buildReaderNextChapterFooter(
    BuildContext context,
    ReaderPageData page,
  ) {
    return SizedBox(
      height: _controller.preferences.isPaged ? 72 : 80,
      child: Center(
        child: _buildReaderChapterBoundaryCue(
          context,
          isPrevious: false,
          compact: false,
          forceVisible: true,
        ),
      ),
    );
  }

  Widget _buildReaderNextChapterCueOverlay(
    BuildContext context,
    ReaderPageData page,
  ) {
    final EdgeInsets viewPadding = MediaQuery.viewPaddingOf(context);
    final bool showPreviousCue =
        _controller.previousChapterPullDistance > 0 ||
        (_controller.isNextChapterLoading &&
            _controller.previousChapterPullDistance > 0);
    final bool showNextCue =
        _controller.nextChapterPullDistance > 0 ||
        (_controller.isNextChapterLoading &&
            _controller.nextChapterPullDistance > 0);
    return Positioned.fill(
      child: Stack(
        children: <Widget>[
          if (showPreviousCue)
            _buildReaderChapterBoundaryCueOverlayEntry(
              context,
              isPrevious: true,
              forceVisible: showPreviousCue,
              viewPadding: viewPadding,
            ),
          if (showNextCue)
            _buildReaderChapterBoundaryCueOverlayEntry(
              context,
              isPrevious: false,
              forceVisible: showNextCue,
              viewPadding: viewPadding,
            ),
        ],
      ),
    );
  }

  Widget _buildReaderChapterBoundaryCueOverlayEntry(
    BuildContext context, {
    required bool isPrevious,
    required bool forceVisible,
    required EdgeInsets viewPadding,
  }) {
    final ReaderPreferences preferences = _controller.preferences;
    final Alignment alignment;
    final EdgeInsets padding;
    if (preferences.isPaged) {
      final bool nextOnRight =
          preferences.readingDirection == ReaderReadingDirection.rightToLeft;
      final bool placeOnRight = isPrevious ? !nextOnRight : nextOnRight;
      alignment = placeOnRight ? Alignment.centerRight : Alignment.centerLeft;
      padding = EdgeInsets.only(
        left: placeOnRight ? 0 : viewPadding.left + 14,
        right: placeOnRight ? viewPadding.right + 14 : 0,
      );
    } else {
      alignment = isPrevious ? Alignment.topCenter : Alignment.bottomCenter;
      padding = EdgeInsets.only(
        top: isPrevious ? viewPadding.top + 18 : 0,
        bottom: isPrevious
            ? 0
            : (viewPadding.bottom > 0 ? viewPadding.bottom : 0) + 18,
      );
    }
    return Align(
      alignment: alignment,
      child: Padding(
        padding: padding,
        child: _buildReaderChapterBoundaryCue(
          context,
          isPrevious: isPrevious,
          compact: true,
          forceVisible: forceVisible,
        ),
      ),
    );
  }

  Widget _buildReaderChapterBoundaryCue(
    BuildContext context, {
    required bool isPrevious,
    required bool compact,
    required bool forceVisible,
  }) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final ReaderPreferences preferences = _controller.preferences;
    final bool isLoading = _controller.isNextChapterLoading;
    final double pullDistance = isPrevious
        ? _controller.previousChapterPullDistance
        : _controller.nextChapterPullDistance;
    final bool isReady =
        (isPrevious
            ? _controller.previousChapterPullReady
            : _controller.nextChapterPullReady) &&
        !isLoading;
    final double triggerDistance = preferences.isPaged ? 152 : 266;
    final double progress = (pullDistance / triggerDistance)
        .clamp(0, 1)
        .toDouble();
    final bool isVisible = forceVisible || isLoading || progress > 0;
    final IconData directionIcon = switch ((
      isPrevious,
      preferences.isPaged,
      preferences.readingDirection,
    )) {
      (false, true, ReaderReadingDirection.leftToRight) =>
        Icons.chevron_left_rounded,
      (false, true, ReaderReadingDirection.rightToLeft) =>
        Icons.chevron_right_rounded,
      (true, true, ReaderReadingDirection.leftToRight) =>
        Icons.chevron_right_rounded,
      (true, true, ReaderReadingDirection.rightToLeft) =>
        Icons.chevron_left_rounded,
      (false, true, _) => Icons.chevron_left_rounded,
      (false, false, _) => Icons.expand_less_rounded,
      (true, false, _) => Icons.expand_more_rounded,
      (true, true, _) => Icons.chevron_right_rounded,
    };
    final String label = isPrevious ? '上一章' : '下一章';
    final Color accentColor = colorScheme.primary;
    final double bgAlpha = compact ? 0.82 : 0.92;
    final double height = compact ? 36.0 : 44.0;
    final double iconSize = compact ? 18.0 : 20.0;
    final double fontSize = compact ? 12.0 : 13.0;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutQuart,
      opacity: !isVisible
          ? 0
          : (isLoading || isReady ? 1 : (0.5 + progress * 0.5).clamp(0, 1)),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutQuart,
        scale: isReady ? 1.0 : 0.88 + (progress * 0.12),
        child: Container(
          height: height,
          padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 18),
          decoration: BoxDecoration(
            color: colorScheme.surface.withValues(alpha: bgAlpha),
            borderRadius: BorderRadius.circular(height / 2),
            border: Border.all(
              color: accentColor.withValues(
                alpha: isReady ? 0.5 : 0.15 + (progress * 0.2),
              ),
              width: isReady ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (isLoading)
                SizedBox.square(
                  dimension: iconSize,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.0,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      accentColor.withValues(alpha: 0.8),
                    ),
                  ),
                )
              else
                Icon(
                  directionIcon,
                  size: iconSize,
                  color: accentColor.withValues(
                    alpha: isReady ? 1 : 0.5 + (progress * 0.5),
                  ),
                ),
              SizedBox(width: compact ? 4 : 6),
              Text(
                isLoading ? '加载中' : (isReady ? '松手跳转' : label),
                style: TextStyle(
                  color: isReady
                      ? accentColor
                      : colorScheme.onSurface.withValues(
                          alpha: 0.6 + (progress * 0.4),
                        ),
                  fontSize: fontSize,
                  fontWeight: isReady ? FontWeight.w700 : FontWeight.w600,
                  height: 1.0,
                ),
              ),
            ],
          ),
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
                    _buildReaderChapterControlsOverlay(context, page),
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
