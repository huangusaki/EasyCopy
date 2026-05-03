// ignore_for_file: use_key_in_widget_constructors

import 'package:easy_copy/easy_copy_screen/models.dart';
import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/widgets/cover_image.dart';
import 'package:easy_copy/widgets/settings_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SurfaceBlock extends StatelessWidget {
  const SurfaceBlock({
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

class SoftSection extends StatelessWidget {
  const SoftSection({
    required this.child,
    this.title,
    this.actionLabel,
    this.onActionTap,
    this.padding = const EdgeInsets.fromLTRB(16, 14, 16, 16),
    super.key,
  });

  final String? title;
  final String? actionLabel;
  final VoidCallback? onActionTap;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (title != null)
            SectionHeader(
              title: title!,
              actionLabel: actionLabel,
              onActionTap: onActionTap,
              padding: const EdgeInsets.only(bottom: 12),
            ),
          child,
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.actionLabel,
    this.onActionTap,
    this.padding = const EdgeInsets.only(bottom: 12),
    super.key,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onActionTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 4,
            height: 18,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: colorScheme.secondary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: colorScheme.onSurface,
                letterSpacing: 0.2,
              ),
            ),
          ),
          if (actionLabel != null && onActionTap != null)
            InkWell(
              onTap: onActionTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      actionLabel!,
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.62),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: colorScheme.onSurface.withValues(alpha: 0.62),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

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

class FeatureBannerCard extends StatelessWidget {
  const FeatureBannerCard({required this.banner, required this.onTap});

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

class TopicIssueList extends StatelessWidget {
  const TopicIssueList({required this.items, required this.onTap});

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
        return TopicIssueRow(
          item: item,
          isLast: index == items.length - 1,
          onTap: () => onTap(item.href),
        );
      }),
    );
  }
}

class TopicIssueRow extends StatelessWidget {
  const TopicIssueRow({
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
                              TopicMetaPill(
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

class TopicMetaPill extends StatelessWidget {
  const TopicMetaPill({required this.label});

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

class PagerCard extends StatelessWidget {
  const PagerCard({
    required this.pager,
    required this.onPrev,
    required this.onNext,
    this.onJumpToPage,
  });

  final PagerData pager;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final ValueChanged<int>? onJumpToPage;

  void _runAction(BuildContext context, VoidCallback? action) {
    FocusScope.of(context).unfocus();
    action?.call();
  }

  Future<void> _openJumpSheet(BuildContext context) async {
    final int? totalPageCount = pager.totalPageCount;
    final int currentPage =
        pager.currentPageNumber ?? int.tryParse(pager.currentLabel) ?? 1;
    final int? target = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (BuildContext sheetContext) {
        return _PagerJumpSheet(
          totalPageCount: totalPageCount,
          currentPage: currentPage,
        );
      },
    );
    if (target != null && context.mounted) {
      onJumpToPage?.call(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final int? totalPageCount = pager.totalPageCount;
    final String currentDisplay =
        pager.currentPageNumber?.toString() ??
        (pager.currentLabel.isEmpty ? '--' : pager.currentLabel);
    final String totalDisplay = totalPageCount?.toString() ?? '';
    final bool jumpable = onJumpToPage != null;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        _PagerSideButton(
          icon: Icons.arrow_back_rounded,
          onPressed: onPrev == null ? null : () => _runAction(context, onPrev),
        ),
        _PagerIndicatorChip(
          current: currentDisplay,
          total: totalDisplay,
          enabled: jumpable,
          onTap: jumpable ? () => _openJumpSheet(context) : null,
        ),
        _PagerSideButton(
          icon: Icons.arrow_forward_rounded,
          onPressed: onNext == null ? null : () => _runAction(context, onNext),
        ),
      ],
    );
  }
}

class _PagerSideButton extends StatelessWidget {
  const _PagerSideButton({required this.icon, this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool enabled = onPressed != null;
    final Color background = enabled
        ? colorScheme.surfaceContainerHigh
        : colorScheme.surfaceContainerLow.withValues(alpha: 0.6);
    final Color foreground = enabled
        ? colorScheme.onSurface
        : colorScheme.onSurface.withValues(alpha: 0.32);
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 48,
          height: 44,
          child: Icon(icon, size: 22, color: foreground),
        ),
      ),
    );
  }
}

class _PagerIndicatorChip extends StatelessWidget {
  const _PagerIndicatorChip({
    required this.current,
    required this.total,
    required this.enabled,
    this.onTap,
  });

  final String current;
  final String total;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool hasTotal = total.isNotEmpty;
    return Material(
      color: colorScheme.secondaryContainer.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                current,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSecondaryContainer,
                  height: 1,
                ),
              ),
              if (hasTotal) ...<Widget>[
                Text(
                  ' / ',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSecondaryContainer.withValues(
                      alpha: 0.55,
                    ),
                    height: 1,
                  ),
                ),
                Text(
                  total,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSecondaryContainer.withValues(
                      alpha: 0.7,
                    ),
                    height: 1,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PagerJumpSheet extends StatefulWidget {
  const _PagerJumpSheet({
    required this.totalPageCount,
    required this.currentPage,
  });

  final int? totalPageCount;
  final int currentPage;

  @override
  State<_PagerJumpSheet> createState() => _PagerJumpSheetState();
}

class _PagerJumpSheetState extends State<_PagerJumpSheet> {
  late int _selectedPage;
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _selectedPage = _clampToRange(widget.currentPage);
    _textController = TextEditingController(text: _selectedPage.toString());
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  int _clampToRange(int value) {
    final int? total = widget.totalPageCount;
    if (total == null || total <= 0) {
      return value < 1 ? 1 : value;
    }
    if (value < 1) return 1;
    if (value > total) return total;
    return value;
  }

  void _setPage(int value, {bool syncText = true}) {
    final int next = _clampToRange(value);
    setState(() {
      _selectedPage = next;
      if (syncText) {
        _textController.value = TextEditingValue(
          text: next.toString(),
          selection: TextSelection.collapsed(offset: next.toString().length),
        );
      }
    });
  }

  void _confirm() {
    Navigator.of(context).pop(_selectedPage);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final int? total = widget.totalPageCount;
    final bool sliderEnabled = total != null && total > 1;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Text(
                  '跳转到指定页',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              if (total != null)
                Text(
                  '共 $total 页',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              _PagerStepButton(
                icon: Icons.first_page_rounded,
                label: '首页',
                onPressed: sliderEnabled ? () => _setPage(1) : null,
              ),
              const SizedBox(width: 8),
              _PagerStepButton(
                icon: Icons.fast_rewind_rounded,
                label: '-10',
                onPressed: sliderEnabled
                    ? () => _setPage(_selectedPage - 10)
                    : null,
              ),
              const Spacer(),
              _PagerStepButton(
                icon: Icons.fast_forward_rounded,
                label: '+10',
                onPressed: sliderEnabled
                    ? () => _setPage(_selectedPage + 10)
                    : null,
              ),
              const SizedBox(width: 8),
              _PagerStepButton(
                icon: Icons.last_page_rounded,
                label: '尾页',
                onPressed: sliderEnabled ? () => _setPage(total) : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (sliderEnabled)
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: colorScheme.primary,
                inactiveTrackColor: colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.6),
                thumbColor: colorScheme.primary,
                overlayColor: colorScheme.primary.withValues(alpha: 0.18),
                trackHeight: 4,
              ),
              child: Slider(
                value: _selectedPage.toDouble().clamp(1, total.toDouble()),
                min: 1,
                max: total.toDouble(),
                divisions: total - 1,
                label: _selectedPage.toString(),
                onChanged: (double value) => _setPage(value.round()),
              ),
            )
          else
            const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _textController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.go,
                  textAlign: TextAlign.center,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: total == null ? '页码' : '1 - $total',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                  ),
                  onChanged: (String value) {
                    final int? parsed = int.tryParse(value.trim());
                    if (parsed != null) {
                      _setPage(parsed, syncText: false);
                    }
                  },
                  onSubmitted: (_) => _confirm(),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: _confirm,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text(
                    '前往',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PagerStepButton extends StatelessWidget {
  const _PagerStepButton({
    required this.icon,
    required this.label,
    this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool enabled = onPressed != null;
    final Color background = enabled
        ? colorScheme.surfaceContainerHigh
        : colorScheme.surfaceContainerLow.withValues(alpha: 0.6);
    final Color foreground = enabled
        ? colorScheme.onSurface
        : colorScheme.onSurface.withValues(alpha: 0.32);
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 16, color: foreground),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PagerNavButton extends StatelessWidget {
  const PagerNavButton({required this.icon, this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool enabled = onPressed != null;
    final Color buttonColor = enabled
        ? colorScheme.surfaceContainerHighest
        : colorScheme.surfaceContainerLow;
    final Color contentColor = enabled
        ? colorScheme.onSurface
        : colorScheme.onSurface.withValues(alpha: 0.32);
    return Material(
      color: buttonColor,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 22, color: contentColor),
        ),
      ),
    );
  }
}

class RankCard extends StatelessWidget {
  const RankCard({required this.item, required this.onTap});

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

class DetailHeroCard extends StatelessWidget {
  const DetailHeroCard({
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
                              (LinkAction author) => LinkChip(
                                label: author.label,
                                active: true,
                                onTap: () => onAuthorTap(author.href),
                              ),
                            )
                          else
                            ...authorLabels.map(
                              (String author) => LinkChip(
                                label: author,
                                active: true,
                                onTap: () => onTagTap(author),
                              ),
                            ),
                          ...page.tags
                              .take(6)
                              .map(
                                (LinkAction tag) => LinkChip(
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

class InfoChip extends StatelessWidget {
  const InfoChip({required this.label, required this.value});

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

class ChapterGrid extends StatelessWidget {
  const ChapterGrid({
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
