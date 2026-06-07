part of '../profile_page_view.dart';

class _VersionEntryCard extends StatelessWidget {
  const _VersionEntryCard({
    required this.versionLabel,
    required this.isCheckingForUpdates,
    this.onCheckForUpdates,
    this.onOpenProjectRepository,
  });

  final String versionLabel;
  final bool isCheckingForUpdates;
  final VoidCallback? onCheckForUpdates;
  final VoidCallback? onOpenProjectRepository;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return _SectionCard(
      title: '版本',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          children: <Widget>[
            _VersionEntryRow(
              label: '当前版本',
              trailing: Text(
                versionLabel,
                style: TextStyle(
                  color: colorScheme.onSurface.withValues(alpha: 0.72),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _VersionEntryDivider(color: colorScheme.outlineVariant),
            _VersionEntryRow(
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
            _VersionEntryDivider(color: colorScheme.outlineVariant),
            _VersionEntryRow(
              label: 'GitHub',
              onTap: onOpenProjectRepository,
              trailing: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

class _VersionEntryRow extends StatelessWidget {
  const _VersionEntryRow({
    required this.label,
    required this.trailing,
    this.onTap,
  });

  final String label;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            IconTheme(
              data: IconThemeData(
                color: colorScheme.onSurface.withValues(alpha: 0.72),
              ),
              child: trailing,
            ),
          ],
        ),
      ),
    );
  }
}

class _VersionEntryDivider extends StatelessWidget {
  const _VersionEntryDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Divider(height: 1, color: color.withValues(alpha: 0.56)),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child, this.title, this.action});

  final String? title;
  final Widget? action;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(title: title, action: action, child: child);
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
              item.title,
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
              item.subtitle,
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
              item.secondaryText,
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
        ),
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
                    item.title,
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
                      item.chapterLabel,
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
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}
