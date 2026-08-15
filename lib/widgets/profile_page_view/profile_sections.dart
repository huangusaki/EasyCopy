part of '../profile_page_view.dart';

/// 设置卡：主题色板铺在卡内，其余设置各占一行，行间用分隔线。
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.themePreference,
    required this.onThemePreferenceChanged,
    required this.wallpaper,
    required this.wallpaperActions,
    required this.chineseConversionMode,
    required this.onChineseConversionModeChanged,
    required this.hostEntry,
    required this.versionLabel,
    required this.isCheckingForUpdates,
    required this.onCheckForUpdates,
    required this.onOpenProjectRepository,
  });

  final AppThemePreference themePreference;
  final ValueChanged<AppThemePreference>? onThemePreferenceChanged;
  final WallpaperPreferences wallpaper;
  final WallpaperEditingActions? wallpaperActions;
  final ChineseConversionMode chineseConversionMode;
  final ValueChanged<ChineseConversionMode>? onChineseConversionModeChanged;
  final Widget? hostEntry;
  final String versionLabel;
  final bool isCheckingForUpdates;
  final VoidCallback? onCheckForUpdates;
  final VoidCallback? onOpenProjectRepository;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final List<Widget> rows = <Widget>[
      if (wallpaperActions != null)
        _WallpaperSettingsEntryRow(
          wallpaper: wallpaper,
          actions: wallpaperActions!,
        ),
      _SettingsEntryRow(
        label: '显示简体',
        trailing: Switch(
          value: chineseConversionMode == ChineseConversionMode.t2s,
          onChanged: onChineseConversionModeChanged == null
              ? null
              : (bool value) {
                  onChineseConversionModeChanged!(
                    value
                        ? ChineseConversionMode.t2s
                        : ChineseConversionMode.disabled,
                  );
                },
        ),
      ),
      if (hostEntry != null) hostEntry!,
      _SettingsEntryRow(label: '当前版本', valueLabel: versionLabel),
      _SettingsEntryRow(
        label: '检查更新',
        onTap: onCheckForUpdates,
        trailing: isCheckingForUpdates
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.chevron_right_rounded),
      ),
      _SettingsEntryRow(
        label: 'GitHub',
        onTap: onOpenProjectRepository,
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    ];

    return AppSurfaceCard(
      title: '设置',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _ThemePreferenceBlock(
            value: themePreference,
            onChanged: onThemePreferenceChanged,
          ),
          for (final Widget row in rows) ...<Widget>[
            _SettingsEntryDivider(color: colorScheme.outlineVariant),
            row,
          ],
        ],
      ),
    );
  }
}

class _SettingsEntryRow extends StatelessWidget {
  const _SettingsEntryRow({
    required this.label,
    this.valueLabel,
    this.trailing,
    this.onTap,
  });

  final String label;
  final String? valueLabel;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: <Widget>[
              Text(
                label,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  valueLabel ?? '',
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (trailing != null) ...<Widget>[
                const SizedBox(width: 8),
                IconTheme(
                  data: IconThemeData(
                    color: colorScheme.onSurface.withValues(alpha: 0.72),
                  ),
                  child: trailing!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsEntryDivider extends StatelessWidget {
  const _SettingsEntryDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, color: color.withValues(alpha: 0.56));
  }
}

class _SectionHeaderAction extends StatelessWidget {
  const _SectionHeaderAction({
    required this.metaText,
    required this.semanticLabel,
    required this.onTap,
  });

  final String metaText;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          metaText,
          style: TextStyle(
            color: colorScheme.onSurface.withValues(alpha: 0.58),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 10),
        _SectionActionButton(semanticLabel: semanticLabel, onTap: onTap),
      ],
    );
  }
}

class _SectionActionButton extends StatelessWidget {
  const _SectionActionButton({
    required this.semanticLabel,
    required this.onTap,
  });

  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Ink(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.72,
              ),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Icon(
              Icons.chevron_right_rounded,
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _LibraryCard extends StatelessWidget {
  const _LibraryCard({
    required this.item,
    required this.onTap,
    this.onLongPress,
  });

  static const double _titleHeight = 33.6;

  final ComicCardData item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: CoverImage(imageUrl: item.coverUrl)),
          const SizedBox(height: 8),
          SizedBox(
            height: _titleHeight,
            child: Text(
              ChineseConverter.instance.convert(item.title),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                height: 1.2,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (item.subtitle.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              ChineseConverter.instance.convert(item.subtitle),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.66),
                fontSize: 11,
              ),
            ),
          ],
          if (item.secondaryText.isNotEmpty) ...<Widget>[
            const SizedBox(height: 3),
            Text(
              ChineseConverter.instance.convert(item.secondaryText),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.item, required this.onTap});

  final ProfileHistoryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    // 条目直接落在卡片上，不再自带一层底：同页的 _LibraryCard 就是这么画的，
    // 而原来那层 surfaceContainerLow 在亮色下和卡片同色（等于没画），
    // 暗色下又比卡片更暗，变成卡片上的一个洞。
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 68,
              height: 92,
              child: CoverImage(imageUrl: item.coverUrl, borderRadius: 16),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    ChineseConverter.instance.convert(item.title),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (item.chapterLabel.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      ChineseConverter.instance.convert(item.chapterLabel),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.76),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  if (item.visitedAt.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 6),
                    Text(
                      item.visitedAt,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.56),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: colorScheme.onSurface.withValues(alpha: 0.42),
            ),
          ],
        ),
      ),
    );
  }
}
