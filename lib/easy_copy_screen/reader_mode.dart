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
                              label: '显示评论页',
                              value: preferences.showChapterComments,
                              onChanged: (bool value) {
                                unawaited(
                                  _preferencesController
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
    if (page.imageUrls.isEmpty) {
      return '-- / --';
    }
    if (_readerPreferences.isPaged) {
      if (_shouldShowReaderCommentTailPage(page) &&
          _currentReaderPageIndex >= page.imageUrls.length) {
        return '评论页';
      }
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
    final bool showCommentTail = _shouldShowReaderCommentTailPage(page);
    final bool hasNextChapter = page.nextHref.trim().isNotEmpty;
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        _handleReaderNextChapterPullNotification(
          notification,
          page: page,
          controller: _readerScrollController,
        );
        return _handleReaderScrollNotification(notification);
      },
      child: ListView.builder(
        key: ValueKey<String>(
          'reader-scroll-${page.uri}-${_readerPreferences.pageFit.name}-$showGap-$showCommentTail',
        ),
        controller: _readerScrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
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
    final bool showCommentTail = _shouldShowReaderCommentTailPage(page);
    final bool hasNextChapter = page.nextHref.trim().isNotEmpty;
    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        final bool isLastReaderPage =
            _currentReaderPageIndex >= _readerPagedPageCount(page) - 1;
        if (isLastReaderPage && hasNextChapter) {
          _handleReaderNextChapterPullNotification(
            notification,
            page: page,
            controller: _readerPageController,
            axis: Axis.horizontal,
          );
        }
        return _handleReaderScrollNotification(notification);
      },
      child: PageView.builder(
        key: ValueKey<String>(
          'reader-paged-${page.uri}-${_readerPreferences.readingDirection.name}-${_readerPreferences.pageFit.name}-${_readerPreferences.showPageGap}-$showCommentTail',
        ),
        controller: _readerPageController,
        physics: const _ReaderPagedScrollPhysics(
          triggerPageRatio: 0.65,
          parent: BouncingScrollPhysics(),
        ),
        reverse: reverse,
        itemCount: _readerPagedPageCount(page),
        onPageChanged: _handleReaderPageChanged,
        itemBuilder: (BuildContext context, int index) {
          final ScrollController scrollController =
              _readerPageScrollControllerFor(index);
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
                      onNotification: _handleReaderScrollNotification,
                      child: SingleChildScrollView(
                        controller: scrollController,
                        physics: const BouncingScrollPhysics(),
                        child: pageBody,
                      ),
                    );
              return Padding(
                padding: _readerPreferences.showPageGap
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
      );
    }

    return ColoredBox(
      color: showGap ? colorScheme.surface : colorScheme.surfaceContainerLowest,
      child: _ReaderChapterImage(
        key: ValueKey<String>('reader-image-$imageUrl-$viewportHeight'),
        imageProvider: imageProvider,
        fit: fit,
        viewportHeight: viewportHeight,
        aspectRatio: _readerImageAspectRatios[imageUrl],
        onResolvedAspectRatio: (double aspectRatio) {
          if (!aspectRatio.isFinite || aspectRatio <= 0) {
            return;
          }
          final double? previousAspectRatio =
              _readerImageAspectRatios[imageUrl];
          if (previousAspectRatio != null &&
              (previousAspectRatio - aspectRatio).abs() < 0.01) {
            return;
          }
          _setStateIfMounted(() {
            _readerImageAspectRatios[imageUrl] = aspectRatio;
          });
        },
      ),
    );
  }

  Widget _buildReaderPagedPageBody(
    BuildContext context, {
    required ReaderPageData page,
    required String imageUrl,
    required BoxConstraints constraints,
    required bool showNextChapterFooter,
  }) {
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
                imageUrl: imageUrl,
                viewportHeight:
                    _readerPreferences.pageFit == ReaderPageFit.fitScreen
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
        _readerCommentsChapterId == _readerChapterIdForPage(page)
        ? _readerChapterComments
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
    final bool isAuthenticated =
        _session.isAuthenticated && (_session.token ?? '').isNotEmpty;
    final Widget actionButton = isAuthenticated
        ? FilledButton(
            onPressed: _isReaderCommentSubmitting
                ? null
                : () => unawaited(_submitReaderComment(page)),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 32),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(_isReaderCommentSubmitting ? '发送中' : '发送'),
          )
        : TextButton(
            onPressed: () => unawaited(_openAuthFlow()),
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
          controller: _readerCommentController,
          enabled: !_isReaderCommentSubmitting,
          readOnly: !isAuthenticated,
          onTap: !isAuthenticated ? () => unawaited(_openAuthFlow()) : null,
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
    if (primaryDelta == null || !_readerCommentScrollController.hasClients) {
      return;
    }
    final ScrollPosition position = _readerCommentScrollController.position;
    final double nextOffset = (position.pixels - primaryDelta)
        .clamp(0.0, position.maxScrollExtent)
        .toDouble();
    if ((nextOffset - position.pixels).abs() < 0.5) {
      return;
    }
    _readerCommentScrollController.jumpTo(nextOffset);
  }

  void _handleReaderCommentCloudDragEnd(DragEndDetails details) {
    if (!_readerCommentScrollController.hasClients) {
      return;
    }
    final double velocity = -(details.primaryVelocity ?? 0);
    if (velocity.abs() < 90) {
      return;
    }
    final ScrollPosition position = _readerCommentScrollController.position;
    if (position.maxScrollExtent <= 0) {
      return;
    }
    final double targetOffset = (position.pixels + (velocity * 0.18))
        .clamp(0.0, position.maxScrollExtent)
        .toDouble();
    if ((targetOffset - position.pixels).abs() < 1) {
      return;
    }
    unawaited(
      _readerCommentScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  Widget _buildReaderCommentScrollStrip({required bool enabled}) {
    if (!enabled) {
      return const SizedBox.shrink();
    }
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
    if (_isReaderCommentsLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_readerCommentsError.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              _readerCommentsError,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.78),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => unawaited(_loadReaderComments(page)),
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
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final _ReaderCommentCloudLayout layout = _buildReaderCommentCloudLayout(
          context,
          comments,
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
                    (_ReaderCommentBubblePlacement placement) => Positioned(
                      left: placement.left,
                      top: placement.top,
                      child: _buildReaderCommentBubble(
                        context,
                        comments[placement.index],
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
                    controller: _readerCommentScrollController,
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

  _ReaderCommentCloudLayout _buildReaderCommentCloudLayout(
    BuildContext context,
    List<ChapterComment> comments, {
    required double maxWidth,
  }) {
    final double availableWidth = maxWidth
        .clamp(120.0, double.infinity)
        .toDouble();
    const double slotWidth = 6;
    const double runSpacing = 6;
    final double maxBubbleWidth = availableWidth >= 420
        ? availableWidth * 0.58
        : availableWidth * 0.74;
    final double minBubbleWidth = math.min(
      maxBubbleWidth,
      availableWidth >= 420 ? 90 : 72,
    );
    final int slotCount = math.max(1, (availableWidth / slotWidth).floor());
    final List<double> skyline = List<double>.filled(slotCount, 0);
    final List<_ReaderCommentBubblePlacement> placements =
        <_ReaderCommentBubblePlacement>[];
    for (int index = 0; index < comments.length; index++) {
      final _ReaderCommentBubbleMetrics metrics = _measureReaderCommentBubble(
        context,
        comments[index],
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
        _ReaderCommentBubblePlacement(
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
    return _ReaderCommentCloudLayout(
      height: contentHeight,
      placements: placements,
    );
  }

  _ReaderCommentBubbleMetrics _measureReaderCommentBubble(
    BuildContext context,
    ChapterComment comment, {
    required double minBubbleWidth,
    required double maxBubbleWidth,
  }) {
    const double horizontalPadding = 12;
    const double verticalPadding = 10;
    const double avatarSize = 22;
    const double avatarGap = 5;
    final TextScaler textScaler = MediaQuery.textScalerOf(context);
    final InlineSpan textSpan = TextSpan(
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        height: 1.25,
      ),
      children: <InlineSpan>[
        TextSpan(text: comment.message),
        if (comment.likeCount != null)
          TextSpan(
            text: ' ${comment.likeCount}',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
      ],
    );
    final TextPainter naturalPainter = TextPainter(
      text: textSpan,
      textDirection: Directionality.of(context),
      textScaler: textScaler,
    )..layout();
    final double bubbleWidth =
        (naturalPainter.width + horizontalPadding + avatarSize + avatarGap)
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
            bubbleWidth - horizontalPadding - avatarSize - avatarGap,
          ),
        );
    final double contentHeight = math.max(avatarSize, painter.height);
    return _ReaderCommentBubbleMetrics(
      width: bubbleWidth,
      height: contentHeight + verticalPadding,
    );
  }

  Widget _buildReaderCommentBubble(
    BuildContext context,
    ChapterComment comment, {
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
    final TextStyle likeStyle = TextStyle(
      color: foregroundColor.withValues(alpha: 0.74),
      fontSize: 10,
      fontWeight: FontWeight.w800,
      height: 1.25,
    );
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: foregroundColor.withValues(alpha: 0.06)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildReaderCommentAvatar(comment.avatarUrl),
              const SizedBox(width: 5),
              Flexible(
                child: RichText(
                  textScaler: MediaQuery.textScalerOf(context),
                  text: TextSpan(
                    style: messageStyle,
                    children: <InlineSpan>[
                      TextSpan(text: comment.message),
                      if (comment.likeCount != null)
                        TextSpan(
                          text: ' ${comment.likeCount}',
                          style: likeStyle,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
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
      height: _readerPreferences.isPaged ? 92 : 112,
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
        _readerPreviousChapterPullDistance > 0 ||
        (_isReaderNextChapterLoading && _readerPreviousChapterPullDistance > 0);
    final bool showNextCue =
        _readerNextChapterPullDistance > 0 ||
        (_isReaderNextChapterLoading && _readerNextChapterPullDistance > 0);
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
    final Alignment alignment;
    final EdgeInsets padding;
    if (_readerPreferences.isPaged) {
      final bool nextOnRight =
          _readerPreferences.readingDirection ==
          ReaderReadingDirection.rightToLeft;
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
    final bool isLoading = _isReaderNextChapterLoading;
    final double pullDistance = isPrevious
        ? _readerPreviousChapterPullDistance
        : _readerNextChapterPullDistance;
    final bool isReady =
        (isPrevious
            ? _readerPreviousChapterPullReady
            : _readerNextChapterPullReady) &&
        !isLoading;
    final double progress = (pullDistance / _readerNextChapterTriggerDistance)
        .clamp(0, 1)
        .toDouble();
    final bool isVisible = forceVisible || isLoading || progress > 0;
    final IconData directionIcon = switch ((
      isPrevious,
      _readerPreferences.isPaged,
      _readerPreferences.readingDirection,
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
      (false, false, _) => Icons.keyboard_arrow_up_rounded,
      (true, false, _) => Icons.keyboard_arrow_down_rounded,
      (true, true, _) => Icons.chevron_right_rounded,
    };
    final Axis axis = _readerNextChapterGestureAxis;
    final double direction = switch ((
      isPrevious,
      _readerPreferences.isPaged,
      axis,
    )) {
      (false, false, Axis.vertical) => -1,
      (true, false, Axis.vertical) => 1,
      (false, true, Axis.horizontal)
          when _readerPreferences.readingDirection ==
              ReaderReadingDirection.rightToLeft =>
        1,
      (true, true, Axis.horizontal)
          when _readerPreferences.readingDirection ==
              ReaderReadingDirection.rightToLeft =>
        -1,
      (false, true, Axis.horizontal) => -1,
      (true, true, Axis.horizontal) => 1,
      _ => -1,
    };
    final double size = compact ? 54 : 72;
    final double ringSize = compact ? 42 : 58;
    final double chevronSpacing = compact ? 7 : 9;
    final Color accentColor = isReady
        ? colorScheme.secondary
        : colorScheme.primary;
    final Color surfaceColor = colorScheme.surface.withValues(
      alpha: compact ? 0.88 : 0.94,
    );
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      opacity: !isVisible
          ? 0
          : (isLoading || progress > 0 ? 1 : (compact ? 0.34 : 0.72)),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        scale: isReady ? 1.08 : 0.94 + (progress * 0.1),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: surfaceColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: accentColor.withValues(
                alpha: 0.22 + (progress * (isReady ? 0.34 : 0.22)),
              ),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: accentColor.withValues(
                  alpha: isReady ? 0.24 : 0.12 + (progress * 0.1),
                ),
                blurRadius: compact ? 16 : 22,
                spreadRadius: compact ? 1 : 2,
              ),
            ],
          ),
          child: SizedBox.square(
            dimension: size,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                SizedBox.square(
                  dimension: ringSize,
                  child: CircularProgressIndicator(
                    strokeWidth: compact ? 2.4 : 2.8,
                    value: isLoading ? null : (forceVisible ? progress : null),
                    backgroundColor: accentColor.withValues(alpha: 0.14),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      accentColor.withValues(alpha: 0.92),
                    ),
                  ),
                ),
                for (int index = 0; index < 3; index += 1)
                  Transform.translate(
                    offset: axis == Axis.horizontal
                        ? Offset(
                            direction *
                                (index - 1) *
                                chevronSpacing *
                                (0.82 + (progress * 0.36)),
                            0,
                          )
                        : Offset(
                            0,
                            direction *
                                (index - 1) *
                                chevronSpacing *
                                (0.82 + (progress * 0.36)),
                          ),
                    child: Opacity(
                      opacity: isLoading
                          ? 0.28 + (index * 0.12)
                          : (0.18 +
                                    (((progress * 1.2) - (index * 0.18))
                                            .clamp(0, 1)
                                            .toDouble() *
                                        0.78))
                                .clamp(0, 1)
                                .toDouble(),
                      child: Icon(
                        directionIcon,
                        size: compact ? 18 : 22,
                        color: accentColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
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

class _ReaderCommentBubbleMetrics {
  const _ReaderCommentBubbleMetrics({
    required this.width,
    required this.height,
  });

  final double width;
  final double height;
}

class _ReaderCommentBubblePlacement {
  const _ReaderCommentBubblePlacement({
    required this.index,
    required this.left,
    required this.top,
    required this.width,
  });

  final int index;
  final double left;
  final double top;
  final double width;
}

class _ReaderCommentCloudLayout {
  const _ReaderCommentCloudLayout({
    required this.height,
    required this.placements,
  });

  final double height;
  final List<_ReaderCommentBubblePlacement> placements;
}

class _ReaderChapterImage extends StatefulWidget {
  const _ReaderChapterImage({
    super.key,
    required this.imageProvider,
    required this.fit,
    required this.onResolvedAspectRatio,
    this.viewportHeight,
    this.aspectRatio,
  });

  final ImageProvider<Object> imageProvider;
  final BoxFit fit;
  final ValueChanged<double> onResolvedAspectRatio;
  final double? viewportHeight;
  final double? aspectRatio;

  @override
  State<_ReaderChapterImage> createState() => _ReaderChapterImageState();
}

class _ReaderChapterImageState extends State<_ReaderChapterImage> {
  ImageStream? _imageStream;
  ImageStreamListener? _imageStreamListener;
  bool _hasFrame = false;
  bool _hasError = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant _ReaderChapterImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageProvider != widget.imageProvider) {
      _hasFrame = false;
      _hasError = false;
      _resolveImage(force: true);
      return;
    }
    if (oldWidget.aspectRatio != widget.aspectRatio &&
        widget.aspectRatio != null &&
        !_hasFrame) {
      setState(() {
        _hasFrame = true;
      });
    }
  }

  @override
  void dispose() {
    _detachImageStream();
    super.dispose();
  }

  void _resolveImage({bool force = false}) {
    final ImageStream newStream = widget.imageProvider.resolve(
      createLocalImageConfiguration(context),
    );
    if (!force && _imageStream?.key == newStream.key) {
      return;
    }
    _detachImageStream();
    _imageStream = newStream;
    _imageStreamListener = ImageStreamListener(
      (ImageInfo imageInfo, bool synchronousCall) {
        final int width = imageInfo.image.width;
        final int height = imageInfo.image.height;
        if (width > 0 && height > 0) {
          widget.onResolvedAspectRatio(width / height);
        }
        if (!mounted || _hasFrame) {
          return;
        }
        setState(() {
          _hasFrame = true;
          _hasError = false;
        });
      },
      onError: (Object error, StackTrace? stackTrace) {
        if (!mounted) {
          return;
        }
        setState(() {
          _hasError = true;
        });
      },
    );
    _imageStream!.addListener(_imageStreamListener!);
  }

  void _detachImageStream() {
    final ImageStream? imageStream = _imageStream;
    final ImageStreamListener? imageStreamListener = _imageStreamListener;
    if (imageStream != null && imageStreamListener != null) {
      imageStream.removeListener(imageStreamListener);
    }
    _imageStream = null;
    _imageStreamListener = null;
  }

  Widget _buildLoadingBox() {
    return Center(
      child: CircularProgressIndicator(
        strokeWidth: widget.viewportHeight == null ? 2.4 : 3,
      ),
    );
  }

  Widget _buildErrorBox() {
    return const Center(child: Icon(Icons.broken_image_outlined, size: 36));
  }

  @override
  Widget build(BuildContext context) {
    final double resolvedAspectRatio = widget.aspectRatio ?? 0.72;
    final Widget image = Image(
      image: widget.imageProvider,
      fit: widget.fit,
      width: double.infinity,
      height: widget.viewportHeight,
      gaplessPlayback: true,
      errorBuilder:
          (BuildContext context, Object error, StackTrace? stackTrace) {
            return SizedBox(
              height: widget.viewportHeight,
              child: _buildErrorBox(),
            );
          },
      frameBuilder:
          (
            BuildContext context,
            Widget child,
            int? frame,
            bool wasSynchronouslyLoaded,
          ) {
            final bool isLoaded =
                wasSynchronouslyLoaded || frame != null || _hasFrame;
            if (widget.viewportHeight != null) {
              return SizedBox(
                height: widget.viewportHeight,
                child: isLoaded ? child : _buildLoadingBox(),
              );
            }
            return AspectRatio(
              aspectRatio: resolvedAspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Positioned.fill(
                    child: isLoaded
                        ? child
                        : (_hasError ? _buildErrorBox() : _buildLoadingBox()),
                  ),
                ],
              ),
            );
          },
    );
    if (widget.viewportHeight != null) {
      return image;
    }
    return RepaintBoundary(child: image);
  }
}

class _ReaderPagedScrollPhysics extends PageScrollPhysics {
  const _ReaderPagedScrollPhysics({this.triggerPageRatio = 0.5, super.parent})
    : assert(triggerPageRatio > 0 && triggerPageRatio < 1);

  final double triggerPageRatio;

  @override
  _ReaderPagedScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return _ReaderPagedScrollPhysics(
      triggerPageRatio: triggerPageRatio,
      parent: buildParent(ancestor),
    );
  }

  double _pageExtent(ScrollMetrics position) {
    if (position is PageMetrics) {
      return position.viewportDimension * position.viewportFraction;
    }
    return position.viewportDimension;
  }

  double _getPage(ScrollMetrics position) {
    if (position is PageMetrics && position.page != null) {
      return position.page!;
    }
    return position.pixels / _pageExtent(position);
  }

  double _getPixels(ScrollMetrics position, double page) {
    return page * _pageExtent(position);
  }

  double _getTargetPixels(
    ScrollMetrics position,
    Tolerance tolerance,
    double velocity,
  ) {
    double page = _getPage(position);
    if (velocity < -tolerance.velocity) {
      page -= triggerPageRatio;
    } else if (velocity > tolerance.velocity) {
      page += triggerPageRatio;
    } else {
      final double nearestPage = page.roundToDouble();
      final double delta = page - nearestPage;
      if (delta <= -triggerPageRatio) {
        page = nearestPage - 1;
      } else if (delta >= triggerPageRatio) {
        page = nearestPage + 1;
      } else {
        page = nearestPage;
      }
      return _getPixels(position, page);
    }
    return _getPixels(position, page.roundToDouble());
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    if ((velocity <= 0.0 && position.pixels <= position.minScrollExtent) ||
        (velocity >= 0.0 && position.pixels >= position.maxScrollExtent)) {
      return super.createBallisticSimulation(position, velocity);
    }
    final Tolerance tolerance = toleranceFor(position);
    final double target = _getTargetPixels(position, tolerance, velocity);
    if (target != position.pixels) {
      return ScrollSpringSimulation(
        spring,
        position.pixels,
        target,
        velocity,
        tolerance: tolerance,
      );
    }
    return null;
  }
}
