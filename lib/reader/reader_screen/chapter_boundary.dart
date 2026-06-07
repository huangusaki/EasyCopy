part of '../reader_screen.dart';

extension _ReaderChapterBoundary on ReaderScreenState {
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

  Widget _buildNextChapterCue(BuildContext context, ReaderPageData page) {
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
            _buildBoundaryCueOverlayEntry(
              context,
              isPrevious: true,
              forceVisible: showPreviousCue,
              viewPadding: viewPadding,
            ),
          if (showNextCue)
            _buildBoundaryCueOverlayEntry(
              context,
              isPrevious: false,
              forceVisible: showNextCue,
              viewPadding: viewPadding,
            ),
        ],
      ),
    );
  }

  Widget _buildBoundaryCueOverlayEntry(
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
}
