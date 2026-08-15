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
        // 排序是动作不是选项，之前跟着 enabled 一起给了"选中"态，
        // 结果一排里有两个 chip 看着都像被选中。
        DetailChapterControlChip(
          label: isAscending ? '正序' : '倒序',
          icon: isAscending
              ? Icons.arrow_upward_rounded
              : Icons.arrow_downward_rounded,
          active: false,
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
    // chip 同样贴在卡片上，暗色下 surfaceContainerLowest 是纯黑，会比卡片更暗。
    final Color raisedSurface = colorScheme.brightness == Brightness.light
        ? colorScheme.surfaceContainerLowest
        : colorScheme.surfaceContainerHighest;
    final Color backgroundColor = enabled && active
        ? colorScheme.primaryContainer.withValues(alpha: 0.78)
        : raisedSurface;
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

    final Widget chipChild = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: 14, color: foregroundColor),
          const SizedBox(width: 6),
        ],
        Text(
          ChineseConverter.instance.convert(label),
          style: TextStyle(
            color: foregroundColor,
            fontSize: 12,
            fontWeight: active ? FontWeight.w800 : FontWeight.w700,
          ),
        ),
      ],
    );
    const EdgeInsets chipPadding = EdgeInsets.symmetric(
      horizontal: 14,
      vertical: 9,
    );
    final BoxDecoration chipDecoration = BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: borderColor),
    );
    final Widget chipBody = usesWideLayout(context)
        ? AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: chipPadding,
            decoration: chipDecoration,
            child: chipChild,
          )
        : Container(
            padding: chipPadding,
            decoration: chipDecoration,
            child: chipChild,
          );

    return Opacity(
      opacity: enabled ? 1 : 0.72,
      child: InkWell(
        onTap: interactive ? onTap : null,
        borderRadius: BorderRadius.circular(999),
        child: chipBody,
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
    final List<LinkAction> options = group.options;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final LinkAction option in options)
              LinkChip(
                label: option.label,
                active: option.active,
                onTap: () => onTap(option.href),
              ),
            if (actionLabel != null && onActionTap != null)
              FilterActionChip(
                label: actionLabel!,
                expanded: actionExpanded,
                onTap: onActionTap!,
              ),
          ],
        ),
      ],
    );
  }
}

class RankFilterGroup extends StatelessWidget {
  const RankFilterGroup({required this.items, required this.onTap});

  final List<LinkAction> items;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Wrap(
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          ChineseConverter.instance.convert(label),
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
      child: Container(
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
              ChineseConverter.instance.convert(label),
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
