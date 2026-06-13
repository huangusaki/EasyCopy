import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:reader/config/app_config.dart';

class DesktopDock extends StatelessWidget {
  const DesktopDock({
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
    super.key,
  });

  static const double bottomOverlayExtent =
      _capsuleHeight + _layoutSlack + _bottomMargin;

  static const double _capsuleHeight = 64;
  static const double _itemExtent = 48;
  static const double _itemGap = 10;
  static const double _capsulePadding = 8;
  static const double _bottomMargin = 18;
  static const double _layoutSlack = 4;
  static const double _horizontalSlack = 12;

  final int selectedIndex;
  final List<AppDestination> destinations;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final double contentWidth =
        destinations.length * _itemExtent +
        (destinations.length - 1) * _itemGap;
    final double capsuleWidth =
        _capsulePadding * 2 + _horizontalSlack * 2 + contentWidth;

    return Padding(
      padding: const EdgeInsets.only(bottom: _bottomMargin),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 560),
        curve: Curves.easeOutCubic,
        builder: (BuildContext context, double t, Widget? child) {
          return Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, 24 * (1 - t)),
              child: child,
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_capsuleHeight / 2),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              width: capsuleWidth,
              height: _capsuleHeight + _layoutSlack,
              padding: const EdgeInsets.all(_capsulePadding),
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(_capsuleHeight / 2),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Center(
                child: SizedBox(
                  width: contentWidth,
                  height: _itemExtent,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 420),
                        curve: Curves.easeOutBack,
                        left: selectedIndex * (_itemExtent + _itemGap),
                        top: 0,
                        width: _itemExtent,
                        height: _itemExtent,
                        child: const _SelectionPill(),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          for (
                            int index = 0;
                            index < destinations.length;
                            index += 1
                          ) ...<Widget>[
                            if (index > 0) const SizedBox(width: _itemGap),
                            _DockItem(
                              destination: destinations[index],
                              isSelected: index == selectedIndex,
                              extent: _itemExtent,
                              onTap: () => onDestinationSelected(index),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectionPill extends StatelessWidget {
  const _SelectionPill();

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[colorScheme.primary, colorScheme.secondary],
        ),
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.38),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
    );
  }
}

class _DockItem extends StatefulWidget {
  const _DockItem({
    required this.destination,
    required this.isSelected,
    required this.extent,
    required this.onTap,
  });

  final AppDestination destination;
  final bool isSelected;
  final double extent;
  final VoidCallback onTap;

  @override
  State<_DockItem> createState() => _DockItemState();
}

class _DockItemState extends State<_DockItem> {
  bool _isHovered = false;

  void _setHovered(bool value) {
    if (_isHovered == value) {
      return;
    }
    setState(() => _isHovered = value);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color foreground = widget.isSelected
        ? colorScheme.onPrimary
        : colorScheme.onSurface.withValues(alpha: _isHovered ? 0.95 : 0.62);

    return Semantics(
      label: widget.destination.label,
      button: true,
      selected: widget.isSelected,
      child: ExcludeSemantics(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => _setHovered(true),
          onExit: (_) => _setHovered(false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onTap,
            child: SizedBox(
              width: widget.extent,
              height: widget.extent,
              child: Center(
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutBack,
                  scale: _isHovered ? 1.08 : 1,
                  child: Icon(
                    widget.destination.icon,
                    size: 23,
                    color: foreground,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
