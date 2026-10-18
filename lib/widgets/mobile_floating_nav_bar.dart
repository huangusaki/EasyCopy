import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reader/config/app_config.dart';
import 'package:reader/widgets/responsive_layout.dart';

class MobileFloatingNavBar extends StatelessWidget {
  const MobileFloatingNavBar({
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
    required this.visibleListenable,
    super.key,
  });

  static const double _barHeight = 62;
  static const double _tabletBarHeight = 68;
  static const double _minimumBottomMargin = 12;

  static double bottomOverlayExtent(
    double systemBottomInset, {
    bool isTablet = false,
  }) =>
      (isTablet ? _tabletBarHeight : _barHeight) +
      (systemBottomInset > _minimumBottomMargin
          ? systemBottomInset
          : _minimumBottomMargin);

  final int selectedIndex;
  final List<AppDestination> destinations;
  final ValueChanged<int> onDestinationSelected;
  final ValueListenable<bool> visibleListenable;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool isTablet = usesAndroidTabletLayout(context);
    final double pillExtent = isTablet ? 52 : 48;

    final Widget bar = SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: _minimumBottomMargin),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isTablet ? 520 : 480),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  height: isTablet ? _tabletBarHeight : _barHeight,
                  padding: EdgeInsets.all(isTablet ? 8 : 7),
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.42),
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.09),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                          final double slotWidth =
                              constraints.maxWidth / destinations.length;
                          return Stack(
                            children: <Widget>[
                              AnimatedPositioned(
                                duration: const Duration(milliseconds: 420),
                                curve: Curves.easeOutBack,
                                left:
                                    selectedIndex * slotWidth +
                                    (slotWidth - pillExtent) / 2,
                                top: 0,
                                bottom: 0,
                                width: pillExtent,
                                child: const _SelectionPill(),
                              ),
                              Row(
                                children: <Widget>[
                                  for (
                                    int index = 0;
                                    index < destinations.length;
                                    index += 1
                                  )
                                    Expanded(
                                      child: _NavItem(
                                        destination: destinations[index],
                                        iconSize: isTablet ? 24 : 22,
                                        isSelected: index == selectedIndex,
                                        onTap: () {
                                          unawaited(
                                            HapticFeedback.selectionClick(),
                                          );
                                          onDestinationSelected(index);
                                        },
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          );
                        },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return ValueListenableBuilder<bool>(
      valueListenable: visibleListenable,
      child: RepaintBoundary(child: bar),
      builder: (BuildContext context, bool visible, Widget? child) {
        return IgnorePointer(
          ignoring: !visible,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 300),
            curve: visible ? Curves.easeOutCubic : Curves.easeInCubic,
            offset: visible ? Offset.zero : const Offset(0, 1.8),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 240),
              opacity: visible ? 1 : 0,
              child: child,
            ),
          ),
        );
      },
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

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.iconSize,
    required this.isSelected,
    required this.onTap,
  });

  final AppDestination destination;
  final double iconSize;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color foreground = isSelected
        ? colorScheme.onPrimary
        : colorScheme.onSurface.withValues(alpha: 0.66);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Semantics(
        button: true,
        selected: isSelected,
        label: destination.label,
        child: Center(
          child: Icon(destination.icon, size: iconSize, color: foreground),
        ),
      ),
    );
  }
}
