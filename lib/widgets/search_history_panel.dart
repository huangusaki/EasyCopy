import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Desktop and mobile share the same history panel and chip styling.
class SearchHistoryPanel extends StatefulWidget {
  const SearchHistoryPanel({
    required this.history,
    required this.onSelect,
    required this.onRemove,
    required this.onClear,
    this.maxHeight = double.infinity,
    super.key,
  });

  final List<String> history;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onRemove;
  final VoidCallback onClear;
  final double maxHeight;

  @override
  State<SearchHistoryPanel> createState() => _SearchHistoryPanelState();
}

class _SearchHistoryPanelState extends State<SearchHistoryPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void dispose() {
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, -0.04),
          end: Offset.zero,
        ).animate(_curve),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1).animate(_curve),
          alignment: Alignment.topCenter,
          child: Material(
            type: MaterialType.transparency,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  constraints: BoxConstraints(maxHeight: widget.maxHeight),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLow.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: colors.outlineVariant.withValues(alpha: 0.4),
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 32,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(
                              Icons.history_rounded,
                              size: 14,
                              color: colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '最近搜索',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            const Spacer(),
                            Tooltip(
                              message: '清空历史',
                              child: InkWell(
                                onTap: widget.onClear,
                                customBorder: const CircleBorder(),
                                child: SizedBox.square(
                                  dimension: _usesTouchTargets(context)
                                      ? 32
                                      : 21,
                                  child: Icon(
                                    Icons.delete_sweep_rounded,
                                    size: 15,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        LayoutBuilder(
                          builder: (BuildContext context, constraints) => Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: <Widget>[
                              for (final String term in widget.history)
                                _HistoryChip(
                                  term: term,
                                  maxWidth: constraints.maxWidth,
                                  onTap: () => widget.onSelect(term),
                                  onRemove: () => widget.onRemove(term),
                                ),
                            ],
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
    );
  }
}

class _HistoryChip extends StatefulWidget {
  const _HistoryChip({
    required this.term,
    required this.maxWidth,
    required this.onTap,
    required this.onRemove,
  });

  final String term;
  final double maxWidth;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  State<_HistoryChip> createState() => _HistoryChipState();
}

class _HistoryChipState extends State<_HistoryChip> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          constraints: BoxConstraints(maxWidth: widget.maxWidth),
          padding: const EdgeInsets.fromLTRB(11, 6, 9, 6),
          decoration: BoxDecoration(
            color: _isHovered
                ? colors.primaryContainer.withValues(alpha: 0.7)
                : colors.surfaceContainerHigh.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Flexible(
                child: Text(
                  widget.term,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _isHovered
                        ? colors.onPrimaryContainer
                        : colors.onSurface.withValues(alpha: 0.85),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 140),
                opacity: _isHovered ? 1 : 0.35,
                child: Tooltip(
                  message: '删除这条历史',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onRemove,
                    child: SizedBox.square(
                      dimension: _usesTouchTargets(context) ? 28 : 13,
                      child: Icon(
                        Icons.close_rounded,
                        size: 13,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _usesTouchTargets(BuildContext context) {
  final TargetPlatform platform = Theme.of(context).platform;
  return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
}
