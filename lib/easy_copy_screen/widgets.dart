part of '../easy_copy_screen.dart';

class _SurfaceBlock extends StatelessWidget {
  const _SurfaceBlock({
    required this.title,
    required this.child,
    this.actionLabel,
    this.onActionTap,
  });

  final String title;
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
            boxShadow: active && enabled
                ? <BoxShadow>[
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.14),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
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

class _ReaderStatusPill extends StatelessWidget {
  const _ReaderStatusPill({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 14, color: foregroundColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: foregroundColor,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
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

class _HeroBannerCard extends StatelessWidget {
  const _HeroBannerCard({required this.banner, required this.onTap});

  final HeroBannerData banner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? const Color(0xFF18222D) : const Color(0xFF102038),
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            _NetworkImageBox(imageUrl: banner.imageUrl, aspectRatio: 1),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: isDark
                      ? const <Color>[Color(0xDD0D1117), Color(0x550D1117)]
                      : const <Color>[Color(0xCC0F1320), Color(0x330F1320)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  Text(
                    banner.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (banner.subtitle.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      banner.subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.84),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
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
                child: _NetworkImageBox(
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
          boxShadow: active
              ? <BoxShadow>[
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.22),
                    blurRadius: 12,
                    offset: Offset(0, 3),
                  ),
                ]
              : null,
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

class _PagerCard extends StatelessWidget {
  const _PagerCard({
    required this.pager,
    required this.onPrev,
    required this.onNext,
  });

  final PagerData pager;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: <Widget>[
          Expanded(
            child: FilledButton.tonal(
              onPressed: onPrev,
              child: const Text('上一页'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              children: <Widget>[
                Text(
                  pager.currentLabel.isEmpty ? '--' : pager.currentLabel,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (pager.totalLabel.isNotEmpty)
                  Text(
                    pager.totalLabel,
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.64),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: FilledButton(onPressed: onNext, child: const Text('下一页')),
          ),
        ],
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
              child: _NetworkImageBox(
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
    required this.onTagTap,
  });

  final DetailPageData page;
  final VoidCallback? onReadNow;
  final VoidCallback? onDownload;
  final ValueChanged<String> onTagTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 122,
                child: _NetworkImageBox(
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
                    if (page.authors.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 10),
                      Text(
                        page.authors,
                        style: TextStyle(
                          color: colorScheme.onSurface.withValues(alpha: 0.72),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: page.tags
                          .take(6)
                          .map(
                            (LinkAction tag) => _LinkChip(
                              label: tag.label,
                              active: false,
                              onTap: () => onTagTap(tag.href),
                            ),
                          )
                          .toList(growable: false),
                    ),
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
                  onPressed: onDownload,
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('缓存章节'),
                ),
              ),
            ],
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

class _CachedComicCard extends StatelessWidget {
  const _CachedComicCard({
    required this.item,
    required this.onTap,
    this.onDelete,
  });

  final CachedComicLibraryEntry item;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  item.coverUrl.isEmpty
                      ? const _PlaceholderImage()
                      : CachedNetworkImage(
                          imageUrl: item.coverUrl,
                          fit: BoxFit.cover,
                          cacheManager: EasyCopyImageCaches.coverCache,
                          errorWidget:
                              (BuildContext context, String url, Object error) {
                                return const _PlaceholderImage();
                              },
                        ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xCC111111),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '${item.cachedChapterCount}话',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (onDelete != null) ...<Widget>[
                          const SizedBox(width: 6),
                          Material(
                            color: const Color(0xCC111111),
                            borderRadius: BorderRadius.circular(999),
                            child: InkWell(
                              onTap: onDelete,
                              borderRadius: BorderRadius.circular(999),
                              child: const Padding(
                                padding: EdgeInsets.all(6),
                                child: Icon(
                                  Icons.delete_outline_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
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
          const SizedBox(height: 8),
          Text(
            item.comicTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          if (item.chapters.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              '最近缓存：${item.chapters.first.chapterTitle}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.64),
                fontSize: 11,
              ),
            ),
          ],
        ],
      ),
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
}

class _NetworkImageBox extends StatelessWidget {
  const _NetworkImageBox({required this.imageUrl, required this.aspectRatio});

  final String imageUrl;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: imageUrl.isEmpty
            ? const _PlaceholderImage()
            : CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                cacheManager: EasyCopyImageCaches.coverCache,
                errorWidget: (BuildContext context, String url, Object error) {
                  return const _PlaceholderImage();
                },
              ),
      ),
    );
  }
}

class _PlaceholderImage extends StatelessWidget {
  const _PlaceholderImage();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colorScheme.surfaceContainerHigh,
            colorScheme.surfaceContainerHighest,
          ],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: 28,
          color: colorScheme.onSurface.withValues(alpha: 0.42),
        ),
      ),
    );
  }
}
