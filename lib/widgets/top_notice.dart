import 'dart:async';

import 'package:flutter/material.dart';

enum TopNoticeTone { info, success, warning, error }

class TopNotice {
  static OverlayEntry? _currentEntry;
  static Timer? _dismissTimer;

  static void show(
    BuildContext context,
    String message, {
    TopNoticeTone tone = TopNoticeTone.info,
    Duration duration = const Duration(seconds: 3),
  }) {
    final String trimmedMessage = message.trim();
    if (trimmedMessage.isEmpty) {
      return;
    }
    final OverlayState? overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      return;
    }
    _dismissTimer?.cancel();
    _removeCurrent();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (BuildContext overlayContext) {
        return _TopNoticeBubble(
          message: trimmedMessage,
          tone: tone,
          onDismissed: () {
            if (identical(_currentEntry, entry)) {
              _dismissTimer?.cancel();
              _dismissTimer = null;
              _currentEntry = null;
            }
            entry.remove();
          },
        );
      },
    );
    _currentEntry = entry;
    overlay.insert(entry);
    _dismissTimer = Timer(duration, () {
      if (identical(_currentEntry, entry)) {
        _currentEntry = null;
        _dismissTimer = null;
      }
      entry.remove();
    });
  }

  static void _removeCurrent() {
    final OverlayEntry? currentEntry = _currentEntry;
    _currentEntry = null;
    currentEntry?.remove();
  }

  static TopNoticeTone toneForMessage(String message) {
    final String normalized = message.trim().toLowerCase();
    if (normalized.isEmpty) {
      return TopNoticeTone.info;
    }
    if (normalized.contains('失败') ||
        normalized.contains('异常') ||
        normalized.contains('错误') ||
        normalized.contains('失效') ||
        normalized.contains('不可用')) {
      return TopNoticeTone.error;
    }
    if (normalized.contains('警告') ||
        normalized.contains('稍后') ||
        normalized.contains('阻止')) {
      return TopNoticeTone.warning;
    }
    if (normalized.contains('已') ||
        normalized.contains('完成') ||
        normalized.contains('恢复') ||
        normalized.contains('继续')) {
      return TopNoticeTone.success;
    }
    return TopNoticeTone.info;
  }
}

class _TopNoticeBubble extends StatelessWidget {
  const _TopNoticeBubble({
    required this.message,
    required this.tone,
    required this.onDismissed,
  });

  final String message;
  final TopNoticeTone tone;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final _TopNoticePalette palette = _paletteFor(colorScheme);
    return IgnorePointer(
      ignoring: false,
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              builder: (BuildContext context, double value, Widget? child) {
                return Transform.translate(
                  offset: Offset(0, -16 * (1 - value)),
                  child: Opacity(opacity: value, child: child),
                );
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onDismissed,
                    borderRadius: BorderRadius.circular(18),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.backgroundColor,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: palette.borderColor,
                          width: 1,
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 13,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Icon(
                              palette.icon,
                              size: 18,
                              color: palette.foregroundColor,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                message,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.foregroundColor,
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  _TopNoticePalette _paletteFor(ColorScheme colorScheme) {
    return switch (tone) {
      TopNoticeTone.success => _TopNoticePalette(
        backgroundColor: colorScheme.tertiaryContainer,
        foregroundColor: colorScheme.onTertiaryContainer,
        borderColor: colorScheme.tertiary.withValues(alpha: 0.34),
        icon: Icons.check_circle_rounded,
      ),
      TopNoticeTone.warning => _TopNoticePalette(
        backgroundColor: colorScheme.secondaryContainer,
        foregroundColor: colorScheme.onSecondaryContainer,
        borderColor: colorScheme.secondary.withValues(alpha: 0.32),
        icon: Icons.warning_amber_rounded,
      ),
      TopNoticeTone.error => _TopNoticePalette(
        backgroundColor: colorScheme.errorContainer,
        foregroundColor: colorScheme.onErrorContainer,
        borderColor: colorScheme.error.withValues(alpha: 0.36),
        icon: Icons.error_rounded,
      ),
      TopNoticeTone.info => _TopNoticePalette(
        backgroundColor: colorScheme.surfaceContainerHigh,
        foregroundColor: colorScheme.onSurface,
        borderColor: colorScheme.outlineVariant,
        icon: Icons.info_rounded,
      ),
    };
  }
}

class _TopNoticePalette {
  const _TopNoticePalette({
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderColor,
    required this.icon,
  });

  final Color backgroundColor;
  final Color foregroundColor;
  final Color borderColor;
  final IconData icon;
}
