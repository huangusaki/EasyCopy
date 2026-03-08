part of '../easy_copy_screen.dart';

extension _EasyCopyScreenReaderMode on _EasyCopyScreenState {
  Future<void> _showReaderSettingsSheet() async {
    if (_isReaderSettingsOpen) {
      return;
    }
    _isReaderSettingsOpen = true;
    _scheduleReaderPresentationSync();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: _buildReaderSettingsSheet,
    );
    _isReaderSettingsOpen = false;
    if (mounted) {
      _scheduleReaderPresentationSync();
    }
  }

  void _toggleReaderChapterControls() {
    if (!mounted) {
      return;
    }
    _setStateIfMounted(() {
      _isReaderChapterControlsVisible = !_isReaderChapterControlsVisible;
    });
  }

  void _hideReaderChapterControls() {
    if (!mounted || !_isReaderChapterControlsVisible) {
      return;
    }
    _setStateIfMounted(() {
      _isReaderChapterControlsVisible = false;
    });
  }

  void _handleReaderTapUp(TapUpDetails details) {
    final BuildContext? viewportContext = _readerViewportKey.currentContext;
    final RenderBox? renderBox =
        viewportContext?.findRenderObject() as RenderBox?;
    final double viewportHeight = renderBox != null && renderBox.hasSize
        ? renderBox.size.height
        : details.localPosition.dy * 2;
    if (details.localPosition.dy <= viewportHeight * 0.5) {
      _hideReaderChapterControls();
      unawaited(_showReaderSettingsSheet());
      return;
    }
    _toggleReaderChapterControls();
  }

  Widget _buildReaderSettingsSheet(BuildContext context) {
    final double maxHeight = MediaQuery.sizeOf(context).height * 0.78;
    return AnimatedBuilder(
      animation: _preferencesController,
      builder: (BuildContext context, Widget? _) {
        final ReaderPreferences preferences = _readerPreferences;
        return SafeArea(
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
                        const Padding(
                          padding: EdgeInsets.fromLTRB(4, 0, 4, 16),
                          child: Text(
                            '菜单',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
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
                                                ReaderScreenOrientation.portrait
                                            ? '竖屏'
                                            : '横屏',
                                      ),
                                    );
                                  })
                                  .toList(growable: false),
                              onChanged: (ReaderScreenOrientation? value) {
                                if (value == null) {
                                  return;
                                }
                                unawaited(
                                  _preferencesController
                                      .updateReaderPreferences(
                                        (ReaderPreferences current) => current
                                            .copyWith(screenOrientation: value),
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
                                if (value == null) {
                                  return;
                                }
                                unawaited(
                                  _preferencesController
                                      .updateReaderPreferences(
                                        (ReaderPreferences current) => current
                                            .copyWith(readingDirection: value),
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
                                if (value == null) {
                                  return;
                                }
                                unawaited(
                                  _preferencesController
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
                                if (value == null) {
                                  return;
                                }
                                unawaited(
                                  _preferencesController
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
                              value: preferences.autoPageTurnSeconds.toDouble(),
                              max: 10,
                              divisions: 10,
                              onChanged: (double value) {
                                unawaited(
                                  _preferencesController
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
                              label: '屏幕常亮',
                              value: preferences.keepScreenOn,
                              onChanged: (bool value) {
                                unawaited(
                                  _preferencesController
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
                                  _preferencesController
                                      .updateReaderPreferences(
                                        (ReaderPreferences current) =>
                                            current.copyWith(showClock: value),
                                      ),
                                );
                              },
                            ),
                            SettingsSwitchRow(
                              label: '显示进度',
                              value: preferences.showProgress,
                              onChanged: (bool value) {
                                unawaited(
                                  _preferencesController
                                      .updateReaderPreferences(
                                        (ReaderPreferences current) => current
                                            .copyWith(showProgress: value),
                                      ),
                                );
                              },
                            ),
                            if (_readerPlatformBridge.isAndroidSupported)
                              SettingsSwitchRow(
                                label: '显示电量',
                                value: preferences.showBattery,
                                onChanged: (bool value) {
                                  unawaited(
                                    _preferencesController
                                        .updateReaderPreferences(
                                          (ReaderPreferences current) => current
                                              .copyWith(showBattery: value),
                                        ),
                                  );
                                },
                              ),
                            SettingsSwitchRow(
                              label: '显示页面间隔',
                              value: preferences.showPageGap,
                              onChanged: (bool value) {
                                unawaited(
                                  _preferencesController
                                      .updateReaderPreferences(
                                        (ReaderPreferences current) => current
                                            .copyWith(showPageGap: value),
                                      ),
                                );
                              },
                            ),
                            if (_readerPlatformBridge.isAndroidSupported)
                              SettingsSwitchRow(
                                label: '使用音量键翻页',
                                value: preferences.useVolumeKeysForPaging,
                                onChanged: (bool value) {
                                  unawaited(
                                    _preferencesController
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
                                  _preferencesController
                                      .updateReaderPreferences(
                                        (ReaderPreferences current) =>
                                            current.copyWith(fullscreen: value),
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
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('确定'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  ScrollController _readerPageScrollControllerFor(int pageIndex) {
    return _readerPageScrollControllers.putIfAbsent(pageIndex, () {
      final ScrollController controller = ScrollController();
      controller.addListener(() => _handleReaderPagedInnerScroll(pageIndex));
      return controller;
    });
  }

  Widget _buildReaderOverlay(BuildContext context, ReaderPageData page) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final EdgeInsets viewPadding = MediaQuery.viewPaddingOf(context);
    return IgnorePointer(
      child: Stack(
        children: <Widget>[
          if (_readerPreferences.showClock)
            Positioned(
              left: 12,
              top: viewPadding.top + 12,
              child: _ReaderStatusPill(
                label: _readerClockLabel(),
                icon: Icons.schedule_rounded,
                backgroundColor: colorScheme.surface.withValues(alpha: 0.88),
                foregroundColor: colorScheme.onSurface,
              ),
            ),
          if (_readerPlatformBridge.isAndroidSupported &&
              _readerPreferences.showBattery)
            Positioned(
              right: 12,
              top: viewPadding.top + 12,
              child: _ReaderStatusPill(
                label: _batteryLevel == null ? '--%' : '${_batteryLevel!}%',
                icon: Icons.battery_std_rounded,
                backgroundColor: colorScheme.surface.withValues(alpha: 0.88),
                foregroundColor: colorScheme.onSurface,
              ),
            ),
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
    if (page.imageUrls.isEmpty) {
      return '-- / --';
    }
    if (_readerPreferences.isPaged) {
      return '${_currentReaderPageIndex + 1} / ${page.imageUrls.length}';
    }
    final int visibleIndex = _currentVisibleReaderImageIndex.clamp(
      0,
      page.imageUrls.length - 1,
    );
    return '${visibleIndex + 1} / ${page.imageUrls.length}';
  }

  Widget _buildReaderChapterControls(
    BuildContext context,
    ReaderPageData page,
  ) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          Expanded(
            child: FilledButton.tonal(
              onPressed: page.prevHref.isEmpty
                  ? null
                  : () => _navigateToHref(page.prevHref),
              child: const Text('上一话'),
            ),
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 88, maxWidth: 120),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (_readerPreferences.showProgress)
                  Text(
                    _readerPageCountLabel(page),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                if (page.chapterTitle.isNotEmpty) ...<Widget>[
                  SizedBox(height: _readerPreferences.showProgress ? 2 : 0),
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
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: page.nextHref.isEmpty
                  ? null
                  : () => _navigateToHref(page.nextHref),
              child: const Text('下一话'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReaderChapterControlsOverlay(
    BuildContext context,
    ReaderPageData page,
  ) {
    final EdgeInsets viewPadding = MediaQuery.viewPaddingOf(context);
    final double horizontalPadding = _readerPreferences.showPageGap ? 12 : 0;
    final double bottomPadding =
        (viewPadding.bottom > 0 ? viewPadding.bottom : 0) + 12;
    return Positioned(
      left: horizontalPadding,
      right: horizontalPadding,
      bottom: bottomPadding,
      child: IgnorePointer(
        ignoring: !_isReaderChapterControlsVisible,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          offset: _isReaderChapterControlsVisible
              ? Offset.zero
              : const Offset(0, 1.08),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            opacity: _isReaderChapterControlsVisible ? 1 : 0,
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
    final bool showGap = _readerPreferences.showPageGap;
    final double topPadding = _readerPreferences.fullscreen && showGap ? 0 : 8;
    return RefreshIndicator(
      onRefresh: _retryCurrentPage,
      child: ListView.builder(
        key: ValueKey<String>(
          'reader-scroll-${page.uri}-${_readerPreferences.pageFit.name}-$showGap',
        ),
        controller: _readerScrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: EdgeInsets.only(top: topPadding, bottom: 16),
        itemCount: page.imageUrls.length,
        itemBuilder: (BuildContext context, int index) {
          return Padding(
            key: _readerImageItemKeyFor(index),
            padding: EdgeInsets.only(bottom: showGap ? 10 : 0),
            child: _buildReaderImageFrame(
              context,
              imageUrl: page.imageUrls[index],
              viewportHeight:
                  _readerPreferences.pageFit == ReaderPageFit.fitScreen
                  ? MediaQuery.sizeOf(context).height * 0.72
                  : null,
            ),
          );
        },
      ),
    );
  }

  Widget _buildReaderPagedContent(BuildContext context, ReaderPageData page) {
    final bool reverse =
        _readerPreferences.readingDirection ==
        ReaderReadingDirection.rightToLeft;
    final double topPadding =
        _readerPreferences.fullscreen && _readerPreferences.showPageGap ? 0 : 8;
    return PageView.builder(
      key: ValueKey<String>(
        'reader-paged-${page.uri}-${_readerPreferences.readingDirection.name}-${_readerPreferences.pageFit.name}-${_readerPreferences.showPageGap}',
      ),
      controller: _readerPageController,
      reverse: reverse,
      itemCount: page.imageUrls.length,
      onPageChanged: _handleReaderPageChanged,
      itemBuilder: (BuildContext context, int index) {
        final ScrollController scrollController =
            _readerPageScrollControllerFor(index);
        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return Padding(
              padding: _readerPreferences.showPageGap
                  ? EdgeInsets.only(top: topPadding, bottom: 8)
                  : EdgeInsets.zero,
              child: SingleChildScrollView(
                controller: scrollController,
                physics: const BouncingScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: _buildReaderImageFrame(
                    context,
                    imageUrl: page.imageUrls[index],
                    viewportHeight:
                        _readerPreferences.pageFit == ReaderPageFit.fitScreen
                        ? constraints.maxHeight
                        : null,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildReaderImageFrame(
    BuildContext context, {
    required String imageUrl,
    double? viewportHeight,
  }) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool showGap = _readerPreferences.showPageGap;
    final BoxFit fit = _readerPreferences.pageFit == ReaderPageFit.fitWidth
        ? BoxFit.fitWidth
        : BoxFit.contain;
    final Uri? parsedUri = Uri.tryParse(imageUrl);
    final bool isLocalFile = parsedUri != null && parsedUri.scheme == 'file';
    final Widget image = isLocalFile
        ? Image.file(
            File.fromUri(parsedUri),
            fit: fit,
            width: double.infinity,
            height: viewportHeight,
            errorBuilder:
                (BuildContext context, Object error, StackTrace? stackTrace) {
                  return SizedBox(
                    height: viewportHeight ?? 220,
                    child: const Center(
                      child: Icon(Icons.broken_image_outlined, size: 36),
                    ),
                  );
                },
          )
        : CachedNetworkImage(
            imageUrl: imageUrl,
            fit: fit,
            width: double.infinity,
            height: viewportHeight,
            cacheManager: EasyCopyImageCaches.readerCache,
            progressIndicatorBuilder:
                (BuildContext context, String url, DownloadProgress progress) {
                  return SizedBox(
                    height: viewportHeight ?? 260,
                    child: Center(
                      child: CircularProgressIndicator(
                        value: progress.progress,
                      ),
                    ),
                  );
                },
            errorWidget: (BuildContext context, String url, Object error) {
              return SizedBox(
                height: viewportHeight ?? 220,
                child: const Center(
                  child: Icon(Icons.broken_image_outlined, size: 36),
                ),
              );
            },
          );

    return ColoredBox(
      color: showGap ? colorScheme.surface : colorScheme.surfaceContainerLowest,
      child: image,
    );
  }

  Widget _buildReaderMode(BuildContext context, ReaderPageData page) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return AnimatedOpacity(
      opacity: _isReaderExitTransitionActive ? 0 : 1,
      duration: _readerExitFadeDuration,
      curve: Curves.easeOutCubic,
      child: IgnorePointer(
        ignoring: _isReaderExitTransitionActive,
        child: Scaffold(
          backgroundColor: colorScheme.surfaceContainerLowest,
          body: SizedBox(
            key: _readerViewportKey,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTapUp: _handleReaderTapUp,
                    child: _readerPreferences.isPaged
                        ? _buildReaderPagedContent(context, page)
                        : _buildReaderScrollableContent(context, page),
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
  }
}
