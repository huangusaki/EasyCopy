// ignore_for_file: use_key_in_widget_constructors

part of '../widgets.dart';

class DetailChapterToolbar extends StatelessWidget {
  const DetailChapterToolbar({
    required this.tabs,
    required this.selectedKey,
    required this.isAscending,
    required this.onSelectTab,
    required this.onToggleSort,
  });

  final List<DetailChapterTabData> tabs;
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
                    (DetailChapterTabData tab) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: DetailChapterControlChip(
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
        DetailChapterControlChip(
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

class DetailChapterControlChip extends StatelessWidget {
  const DetailChapterControlChip({
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

class FilterGroup extends StatelessWidget {
  const FilterGroup({
    required this.group,
    required this.onTap,
    this.actionLabel,
    this.onActionTap,
    this.actionExpanded = false,
  });

  final FilterGroupData group;
  final ValueChanged<String> onTap;
  final String? actionLabel;
  final VoidCallback? onActionTap;
  final bool actionExpanded;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            group.label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: group.options
              .map<Widget>(
                (LinkAction option) => LinkChip(
                  label: option.label,
                  active: option.active,
                  onTap: () => onTap(option.href),
                ),
              )
              .followedBy(
                actionLabel != null && onActionTap != null
                    ? <Widget>[
                        FilterActionChip(
                          label: actionLabel!,
                          expanded: actionExpanded,
                          onTap: onActionTap!,
                        ),
                      ]
                    : const <Widget>[],
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}

class RankFilterGroup extends StatelessWidget {
  const RankFilterGroup({
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
                (LinkAction item) => LinkChip(
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

class LinkChip extends StatelessWidget {
  const LinkChip({
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
        ? colorScheme.secondaryContainer
        : colorScheme.surfaceContainerLow;
    final Color borderColor = active
        ? colorScheme.outline.withValues(alpha: 0.82)
        : colorScheme.outlineVariant;
    final Color textColor = active
        ? colorScheme.onSecondaryContainer
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

class FilterActionChip extends StatelessWidget {
  const FilterActionChip({
    required this.label,
    required this.expanded,
    required this.onTap,
  });

  final String label;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: colorScheme.primary.withValues(alpha: 0.18),
          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.9)),
          borderRadius: BorderRadius.circular(999),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: colorScheme.primary.withValues(alpha: 0.16),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colorScheme.primary,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              size: 16,
              color: colorScheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}
