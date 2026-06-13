import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:reader/widgets/desktop/desktop_window_controls.dart';
import 'package:window_manager/window_manager.dart';

class DesktopFloatingWindowControls extends StatefulWidget {
  const DesktopFloatingWindowControls({super.key});

  @override
  State<DesktopFloatingWindowControls> createState() =>
      _DesktopFloatingWindowControlsState();
}

class _DesktopFloatingWindowControlsState
    extends State<DesktopFloatingWindowControls> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        opacity: _isHovered ? 1 : 0.3,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          offset: _isHovered ? Offset.zero : const Offset(0, -0.08),
          child: Padding(
            padding: const EdgeInsets.only(top: 8, right: 10),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (_) => windowManager.startDragging(),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.move,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 6,
                            ),
                            child: Icon(
                              Icons.drag_indicator_rounded,
                              size: 15,
                              color: colorScheme.onSurfaceVariant.withValues(
                                alpha: 0.7,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const DesktopWindowControls(),
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
