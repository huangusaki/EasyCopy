part of '../easy_copy_screen.dart';

class _SurfaceBlock extends StatelessWidget {
  const _SurfaceBlock({
    this.title,
    required this.child,
    this.actionLabel,
    this.onActionTap,
  });

  final String? title;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onActionTap;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      title: title,
      action: actionLabel != null && onActionTap != null
          ? TextButton(onPressed: onActionTap, child: Text(actionLabel!))
          : null,
      child: child,
    );
  }
}

class _DetailChapterToolbar extends StatelessWidget {
  const _DetailChapterToolbar({
    required this.tabs,
    required this.selectedKey,
    required this.isAscending,
    required this.onSelectTab,
    required this.onToggleSort,
  });

  final List<_DetailChapterTabData> tabs;
  final String? selectedKey;
  final bool isAscending;
  final ValueChanged<String> onSelectTab;
  final VoidCallback? onToggleSort;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: tabs
                  .map(
                    (_DetailChapterTabData tab) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _DetailChapterControlChip(
                        label: tab.label,
                        active: tab.key == selectedKey,
                        enabled: tab.enabled,
                        onTap: tab.enabled ? () => onSelectTab(tab.key) : null,
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _DetailChapterControlChip(
          label: isAscending ? '正序' : '倒序',
          icon: isAscending
              ? Icons.arrow_upward_rounded
              : Icons.arrow_downward_rounded,
          active: onToggleSort != null,
          enabled: onToggleSort != null,
          onTap: onToggleSort,
        ),
      ],
    );
  }
}

class _DetailChapterControlChip extends StatelessWidget {
  const _DetailChapterControlChip({
    required this.label,
    required this.active,
    required this.enabled,
    this.icon,
    this.onTap,
  });

  final String label;
  final bool active;
  final bool enabled;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool interactive = enabled && onTap != null;
    final Color backgroundColor = !enabled
        ? colorScheme.surfaceContainerLow
        : active
        ? colorScheme.primaryContainer.withValues(alpha: 0.78)
        : colorScheme.surfaceContainerLowest;
    final Color borderColor = !enabled
        ? colorScheme.outlineVariant.withValues(alpha: 0.45)
        : active
        ? colorScheme.primary.withValues(alpha: 0.86)
        : colorScheme.outlineVariant;
    final Color foregroundColor = !enabled
        ? colorScheme.onSurface.withValues(alpha: 0.42)
        : active
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;

    return Opacity(
      opacity: enabled ? 1 : 0.72,
      child: InkWell(
        onTap: interactive ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 14, color: foregroundColor),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: foregroundColor,
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReaderStatusLabel extends StatelessWidget {
  const _ReaderStatusLabel({
    required this.label,
    this.icon,
    this.fontSize = 14,
  });

  final String label;
  final IconData? icon;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Icon(icon, size: fontSize + 4, color: Colors.black),
                Icon(icon, size: fontSize + 1, color: Colors.white),
              ],
            ),
            const SizedBox(width: 3),
          ],
          _ReaderOutlinedText(label: label, fontSize: fontSize),
        ],
      ),
    );
  }
}

class _ReaderOutlinedText extends StatelessWidget {
  const _ReaderOutlinedText({required this.label, required this.fontSize});

  final String label;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final Paint strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.black;
    return Stack(
      children: <Widget>[
        Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            height: 1,
            foreground: strokePaint,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ],
    );
  }
}

class _ReaderSheetSwipeDismissRegion extends StatefulWidget {
  const _ReaderSheetSwipeDismissRegion({
    required this.child,
    required this.onDismiss,
    required this.dismissDistance,
  });

  final Widget child;
  final VoidCallback onDismiss;
  final double dismissDistance;

  @override
  State<_ReaderSheetSwipeDismissRegion> createState() =>
      _ReaderSheetSwipeDismissRegionState();
}

class _ReaderSheetSwipeDismissRegionState
    extends State<_ReaderSheetSwipeDismissRegion> {
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

@immutable
class _AppliedReaderEnvironment {
  const _AppliedReaderEnvironment.standard()
    : orientation = ReaderScreenOrientation.portrait,
      fullscreen = false,
      keepScreenOn = false,
      volumePagingEnabled = false,
      isReader = false;

  const _AppliedReaderEnvironment.reader({
    required this.orientation,
    required this.fullscreen,
    required this.keepScreenOn,
    required this.volumePagingEnabled,
  }) : isReader = true;

  final ReaderScreenOrientation orientation;
  final bool fullscreen;
  final bool keepScreenOn;
  final bool volumePagingEnabled;
  final bool isReader;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is _AppliedReaderEnvironment &&
        other.orientation == orientation &&
        other.fullscreen == fullscreen &&
        other.keepScreenOn == keepScreenOn &&
        other.volumePagingEnabled == volumePagingEnabled &&
        other.isReader == isReader;
  }

  @override
  int get hashCode => Object.hash(
    orientation,
    fullscreen,
    keepScreenOn,
    volumePagingEnabled,
    isReader,
  );
}

class _FeatureBannerCard extends StatelessWidget {
  const _FeatureBannerCard({required this.banner, required this.onTap});

  final HeroBannerData banner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Ink(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? <Color>[
                    colorScheme.surfaceContainerHigh,
                    colorScheme.surfaceContainerHighest,
                  ]
                : const <Color>[Color(0xFFFFEEE1), Color(0xFFFFD1B8)],
          ),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '专题精选',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: isDark
                          ? colorScheme.secondary
                          : const Color(0xFF995630),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    banner.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (banner.subtitle.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      banner.subtitle,
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.76),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 14),
            SizedBox(
              width: 116,
              height: 116,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: EasyCopyCoverImage(
                  imageUrl: banner.imageUrl,
                  aspectRatio: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopicIssueList extends StatelessWidget {
  const _TopicIssueList({required this.items, required this.onTap});

  final List<ComicCardData> items;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Text(
        '还没有可显示的专题。',
        style: TextStyle(
          color: Theme.of(
            context,
          ).colorScheme.onSurface.withValues(alpha: 0.68),
        ),
      );
    }
    return Column(
      children: List<Widget>.generate(items.length, (int index) {
        final ComicCardData item = items[index];
        return _TopicIssueRow(
          item: item,
          isLast: index == items.length - 1,
          onTap: () => onTap(item.href),
        );
      }),
    );
  }
}

class _TopicIssueRow extends StatelessWidget {
  const _TopicIssueRow({
    required this.item,
    required this.isLast,
    required this.onTap,
  });

  final ComicCardData item;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: <Widget>[
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 104,
                    height: 132,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: EasyCopyCoverImage(
                        imageUrl: item.coverUrl,
                        aspectRatio: 0.8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: <Widget>[
                            if (item.badge.trim().isNotEmpty)
                              _TopicMetaPill(
                                label: item.badge.replaceAll('專題', '专题'),
                              ),
                            if (item.secondaryText.trim().isNotEmpty)
                              Text(
                                item.secondaryText,
                                style: TextStyle(
                                  color: colorScheme.onSurface.withValues(
                                    alpha: 0.56,
                                  ),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 20,
                            height: 1.15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (item.subtitle.trim().isNotEmpty) ...<Widget>[
                          const SizedBox(height: 10),
                          Text(
                            item.subtitle,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.72,
                              ),
                              height: 1.45,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (!isLast) ...<Widget>[
          const SizedBox(height: 8),
          Divider(color: colorScheme.outlineVariant, height: 1),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _TopicMetaPill extends StatelessWidget {
  const _TopicMetaPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: TextStyle(
            color: colorScheme.onPrimaryContainer,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _FilterGroup extends StatelessWidget {
  const _FilterGroup({
    required this.group,
    required this.onTap,
    this.actionLabel,
    this.onActionTap,
  });

  final FilterGroupData group;
  final ValueChanged<String> onTap;
  final String? actionLabel;
  final VoidCallback? onActionTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  group.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (actionLabel != null && onActionTap != null)
                TextButton(
                  onPressed: onActionTap,
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(actionLabel!),
                ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: group.options
              .map(
                (LinkAction option) => _LinkChip(
                  label: option.label,
                  active: option.active,
                  onTap: () => onTap(option.href),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _RankFilterGroup extends StatelessWidget {
  const _RankFilterGroup({
    required this.label,
    required this.items,
    required this.onTap,
  });

  final String label;
  final List<LinkAction> items;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items
              .map(
                (LinkAction item) => _LinkChip(
                  label: item.label,
                  active: item.active,
                  onTap: () => onTap(item.href),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}

class _LinkChip extends StatelessWidget {
  const _LinkChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color backgroundColor = active
        ? colorScheme.primaryContainer.withValues(alpha: 0.76)
        : colorScheme.surfaceContainerLow;
    final Color borderColor = active
        ? colorScheme.primary.withValues(alpha: 0.82)
        : colorScheme.outlineVariant;
    final Color textColor = active
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: textColor,
            fontWeight: active ? FontWeight.w800 : FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _PagerCard extends StatefulWidget {
  const _PagerCard({
    required this.pager,
    required this.onPrev,
    required this.onNext,
    this.onJumpToPage,
  });

  final PagerData pager;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final ValueChanged<int>? onJumpToPage;

  @override
  State<_PagerCard> createState() => _PagerCardState();
}

class _PagerCardState extends State<_PagerCard> {
  late final TextEditingController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = TextEditingController(
      text: _pageTextForPager(widget.pager),
    );
  }

  @override
  void didUpdateWidget(covariant _PagerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pager.currentLabel != widget.pager.currentLabel ||
        oldWidget.pager.totalLabel != widget.pager.totalLabel) {
      _pageController.value = TextEditingValue(
        text: _pageTextForPager(widget.pager),
        selection: TextSelection.collapsed(
          offset: _pageTextForPager(widget.pager).length,
        ),
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _pageTextForPager(PagerData pager) {
    return pager.currentPageNumber?.toString() ?? pager.currentLabel;
  }

  void _runAction(VoidCallback? action) {
    FocusScope.of(context).unfocus();
    action?.call();
  }

  void _submitJump() {
    final int? targetPage = int.tryParse(_pageController.text.trim());
    if (targetPage == null) {
      return;
    }
    _runAction(() => widget.onJumpToPage?.call(targetPage));
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final int? totalPageCount = widget.pager.totalPageCount;
    final String currentDisplay =
        widget.pager.currentPageNumber?.toString() ??
        (widget.pager.currentLabel.isEmpty ? '--' : widget.pager.currentLabel);
    final String indicatorLabel = totalPageCount == null
        ? currentDisplay
        : '$currentDisplay / $totalPageCount';
    return AppSurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              _PagerNavButton(
                icon: Icons.arrow_back_rounded,
                label: '上一页',
                onPressed: widget.onPrev == null
                    ? null
                    : () => _runAction(widget.onPrev),
              ),
              Expanded(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(
                        alpha: 0.56,
                      ),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      indicatorLabel,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
              ),
              _PagerNavButton(
                icon: Icons.arrow_forward_rounded,
                label: '下一页',
                reverse: true,
                onPressed: widget.onNext == null
                    ? null
                    : () => _runAction(widget.onNext),
              ),
            ],
          ),
          if (widget.onJumpToPage != null) ...<Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Container(
                height: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  '跳至第',
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.62),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 64,
                  child: TextField(
                    controller: _pageController,
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.go,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurface,
                    ),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    onSubmitted: (_) => _submitJump(),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: colorScheme.surfaceContainerLow,
                      hintText: totalPageCount == null
                          ? '--'
                          : '1-$totalPageCount',
                      hintStyle: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.32),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: colorScheme.outlineVariant,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: colorScheme.outlineVariant,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(
                          color: colorScheme.primary,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '页',
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.62),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 38,
                  child: FilledButton(
                    onPressed: _submitJump,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      '前往',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PagerNavButton extends StatelessWidget {
  const _PagerNavButton({
    required this.icon,
    required this.label,
    this.onPressed,
    this.reverse = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool reverse;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool enabled = onPressed != null;
    final Color buttonColor = enabled
        ? colorScheme.surfaceContainerHigh
        : colorScheme.surfaceContainerLow;
    final Color contentColor = enabled
        ? colorScheme.onSurface
        : colorScheme.onSurface.withValues(alpha: 0.36);
    return Material(
      color: buttonColor,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: reverse
                ? <Widget>[
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: contentColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(icon, size: 16, color: contentColor),
                  ]
                : <Widget>[
                    Icon(icon, size: 16, color: contentColor),
                    const SizedBox(width: 4),
                    Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: contentColor,
                      ),
                    ),
                  ],
          ),
        ),
      ),
    );
  }
}

class _RankCard extends StatelessWidget {
  const _RankCard({required this.item, required this.onTap});

  final RankEntryData item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final IconData trendIcon;
    final Color trendColor;
    switch (item.trend) {
      case 'up':
        trendIcon = Icons.trending_up_rounded;
        trendColor = const Color(0xFF18A558);
      case 'down':
        trendIcon = Icons.trending_down_rounded;
        trendColor = const Color(0xFFD64545);
      default:
        trendIcon = Icons.trending_flat_rounded;
        trendColor = const Color(0xFF7A8494);
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colorScheme.secondary,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                item.rankLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 86,
              height: 112,
              child: EasyCopyCoverImage(
                imageUrl: item.coverUrl,
                aspectRatio: 0.72,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.2,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (item.authors.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      item.authors,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.72),
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          item.heat,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colorScheme.onSurface.withValues(
                              alpha: 0.78,
                            ),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: trendColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(trendIcon, size: 16, color: trendColor),
                            const SizedBox(width: 4),
                            Text(
                              item.trend,
                              style: TextStyle(
                                color: trendColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailHeroCard extends StatelessWidget {
  const _DetailHeroCard({
    required this.page,
    required this.onReadNow,
    required this.onDownload,
    required this.onToggleCollection,
    required this.isCollectionBusy,
    required this.onTagTap,
    required this.onAuthorTap,
  });

  final DetailPageData page;
  final VoidCallback? onReadNow;
  final VoidCallback? onDownload;
  final VoidCallback? onToggleCollection;
  final bool isCollectionBusy;
  final ValueChanged<String> onTagTap;
  final ValueChanged<String> onAuthorTap;

  List<String> _searchLabels(String value) {
    final List<String> labels = <String>[];
    for (final String segment in value.split(RegExp(r'\s*[\/／]\s*'))) {
      final String normalized = segment.trim();
      if (normalized.isEmpty || labels.contains(normalized)) {
        continue;
      }
      labels.add(normalized);
    }
    if (labels.isEmpty && value.trim().isNotEmpty) {
      labels.add(value.trim());
    }
    return labels;
  }

  @override
  Widget build(BuildContext context) {
    final List<String> authorLabels = _searchLabels(page.authors);
    return AppSurfaceCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 122,
                child: EasyCopyCoverImage(
                  imageUrl: page.coverUrl,
                  aspectRatio: 0.72,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      page.title,
                      style: const TextStyle(
                        fontSize: 24,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (page.authorLinks.isNotEmpty ||
                        authorLabels.isNotEmpty ||
                        page.tags.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          if (page.authorLinks.isNotEmpty)
                            ...page.authorLinks.map(
                              (LinkAction author) => _LinkChip(
                                label: author.label,
                                active: true,
                                onTap: () => onAuthorTap(author.href),
                              ),
                            )
                          else
                            ...authorLabels.map(
                              (String author) => _LinkChip(
                                label: author,
                                active: true,
                                onTap: () => onTagTap(author),
                              ),
                            ),
                          ...page.tags
                              .take(6)
                              .map(
                                (LinkAction tag) => _LinkChip(
                                  label: tag.label,
                                  active: true,
                                  onTap: () => onTagTap(tag.label),
                                ),
                              ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: onReadNow,
                  icon: const Icon(Icons.chrome_reader_mode_rounded),
                  label: const Text('开始阅读'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: isCollectionBusy ? null : onToggleCollection,
                  icon: isCollectionBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          page.isCollected
                              ? Icons.bookmark_remove_rounded
                              : Icons.bookmark_add_rounded,
                        ),
                  label: Text(page.isCollected ? '取消收藏' : '加入书架'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: onDownload,
              icon: const Icon(Icons.download_rounded),
              label: const Text('缓存章节'),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 132),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.62),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _ChapterGrid extends StatelessWidget {
  const _ChapterGrid({
    required this.chapters,
    required this.onTap,
    this.downloadedChapterPathKeys = const <String>{},
    this.lastReadChapterPathKey = '',
    this.itemKeyBuilder,
  });

  final List<ChapterData> chapters;
  final ValueChanged<String> onTap;
  final Set<String> downloadedChapterPathKeys;
  final String lastReadChapterPathKey;
  final GlobalKey Function(String chapterPathKey)? itemKeyBuilder;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    const Color lastReadColor = Color(0xFF1F4B99);
    const Color lastReadBorderColor = Color(0xFF173872);
    final bool showsLastReadState = lastReadChapterPathKey.isNotEmpty;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: chapters.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: showsLastReadState ? 2.15 : 2.42,
      ),
      itemBuilder: (BuildContext context, int index) {
        final ChapterData chapter = chapters[index];
        final String chapterPathKey = Uri.tryParse(chapter.href) == null
            ? ''
            : Uri(path: Uri.parse(chapter.href).path).toString();
        final bool isDownloaded = downloadedChapterPathKeys.contains(
          chapterPathKey,
        );
        final bool isLastRead =
            lastReadChapterPathKey.isNotEmpty &&
            chapterPathKey == lastReadChapterPathKey;
        final Widget child = InkWell(
          onTap: () => onTap(chapter.href),
          borderRadius: BorderRadius.circular(18),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isLastRead
                  ? lastReadColor
                  : isDownloaded
                  ? colorScheme.primaryContainer.withValues(alpha: 0.38)
                  : colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(18),
              border: isLastRead
                  ? Border.all(color: lastReadBorderColor, width: 1.2)
                  : isDownloaded
                  ? Border.all(color: const Color(0xFF18A558))
                  : null,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        chapter.label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.1,
                          fontWeight: FontWeight.w800,
                          color: isLastRead ? Colors.white : null,
                        ),
                      ),
                      if (isLastRead) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          '上次看到这里',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.84),
                            fontSize: 10,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (isLastRead || isDownloaded) ...<Widget>[
                  const SizedBox(width: 6),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      if (isLastRead)
                        const Icon(
                          Icons.bookmark_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                      if (isDownloaded) ...<Widget>[
                        if (isLastRead) const SizedBox(height: 4),
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 16,
                          color: Color(0xFF18A558),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
        final GlobalKey? itemKey = itemKeyBuilder?.call(chapterPathKey);
        return itemKey == null
            ? child
            : KeyedSubtree(key: itemKey, child: child);
      },
    );
  }
}

class _ChapterPickerSection {
  const _ChapterPickerSection({required this.label, required this.chapters});

  final String label;
  final List<ChapterData> chapters;
}

class _DetailChapterTabData {
  const _DetailChapterTabData({
    required this.key,
    required this.label,
    required this.chapters,
  });

  final String key;
  final String label;
  final List<ChapterData> chapters;

  bool get enabled => chapters.isNotEmpty;
}

class _AdjacentChapterLinks {
  const _AdjacentChapterLinks({this.prevHref = '', this.nextHref = ''});

  final String prevHref;
  final String nextHref;
}

class _CachedChapterNavigationContext {
  const _CachedChapterNavigationContext({
    this.prevHref = '',
    this.nextHref = '',
    this.catalogHref = '',
  });

  final String prevHref;
  final String nextHref;
  final String catalogHref;

  bool get hasAnyValue =>
      prevHref.trim().isNotEmpty ||
      nextHref.trim().isNotEmpty ||
      catalogHref.trim().isNotEmpty;

  _CachedChapterNavigationContext copyWith({
    String? prevHref,
    String? nextHref,
    String? catalogHref,
  }) {
    return _CachedChapterNavigationContext(
      prevHref: prevHref ?? this.prevHref,
      nextHref: nextHref ?? this.nextHref,
      catalogHref: catalogHref ?? this.catalogHref,
    );
  }

  _CachedChapterNavigationContext mergeMissing(
    _CachedChapterNavigationContext fallback,
  ) {
    return _CachedChapterNavigationContext(
      prevHref: prevHref.trim().isNotEmpty ? prevHref : fallback.prevHref,
      nextHref: nextHref.trim().isNotEmpty ? nextHref : fallback.nextHref,
      catalogHref: catalogHref.trim().isNotEmpty
          ? catalogHref
          : fallback.catalogHref,
    );
  }
}
