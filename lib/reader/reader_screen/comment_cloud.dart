part of '../reader_screen.dart';

extension _ReaderCommentCloud on ReaderScreenState {
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

  void _handleCommentDragUpdate(DragUpdateDetails details) {
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

  void _handleCommentDragEnd(DragEndDetails details) {
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
          onVerticalDragUpdate: _handleCommentDragUpdate,
          onVerticalDragEnd: _handleCommentDragEnd,
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
      return _buildReaderCommentEmptyState(colorScheme);
    }
    final List<ReaderCommentCluster> clusters = buildReaderCommentClusters(
      comments,
    );
    if (clusters.isEmpty) {
      return _buildReaderCommentEmptyState(colorScheme);
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

  Widget _buildReaderCommentEmptyState(ColorScheme colorScheme) {
    return ReaderCommentEmptyStateLayout(
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
        cacheManager: AppImageCaches.readerCache,
        errorWidget: (BuildContext context, String url, Object error) {
          return const CircleAvatar(
            radius: 11,
            child: Icon(Icons.person_rounded, size: 13),
          );
        },
      ),
    );
  }
}
