import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reader/config/app_config.dart';

class MobileFloatingNavBar extends StatelessWidget {
  const MobileFloatingNavBar({
    required this.selectedIndex,
    required this.destinations,
    required this.onDestinationSelected,
    required this.visibleListenable,
    super.key,
  });

  static const double _barHeight = 62;

  final int selectedIndex;
  final List<AppDestination> destinations;
  final ValueChanged<int> onDestinationSelected;
  final ValueListenable<bool> visibleListenable;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    final Widget bar = SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Container(
          height: _barHeight,
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: colorScheme.surface.withValues(alpha: 0.94),
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
          child: Row(
            children: <Widget>[
              for (int index = 0; index < destinations.length; index += 1)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _NavItem(
                      destination: destinations[index],
                      isSelected: index == selectedIndex,
                      onTap: () {
                        unawaited(HapticFeedback.selectionClick());
                        onDestinationSelected(index);
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return ValueListenableBuilder<bool>(
      valueListenable: visibleListenable,
      child: RepaintBoundary(child: bar),
      builder: (BuildContext context, bool visible, Widget? child) {
        return AnimatedSlide(
          duration: const Duration(milliseconds: 300),
          curve: visible ? Curves.easeOutCubic : Curves.easeInCubic,
          offset: visible ? Offset.zero : const Offset(0, 1.8),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 240),
            opacity: visible ? 1 : 0,
            child: child,
          ),
        );
      },
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.destination,
    required this.isSelected,
    required this.onTap,
  });

  final AppDestination destination;
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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          height: 48,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[colorScheme.primary, colorScheme.secondary],
                  )
                : null,
            borderRadius: BorderRadius.circular(999),
            boxShadow: <BoxShadow>[
              if (isSelected)
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
            ],
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 140),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeOutCubic,
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(opacity: animation, child: child);
              },
              child: isSelected
                  ? FittedBox(
                      key: const ValueKey<String>('selected'),
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(destination.icon, size: 22, color: foreground),
                          const SizedBox(width: 7),
                          Text(
                            destination.label,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                              color: foreground,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Icon(
                      destination.icon,
                      key: const ValueKey<String>('idle'),
                      size: 22,
                      color: foreground,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
