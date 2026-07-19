import 'package:flutter/material.dart';
import 'package:reader/widgets/desktop/desktop_window_controls.dart';
import 'package:window_manager/window_manager.dart';

class DesktopTitleBar extends StatelessWidget {
  const DesktopTitleBar({
    required this.title,
    required this.showBackButton,
    required this.onBack,
    required this.isLoading,
    required this.onRefresh,
    this.onOpenShortcuts,
    this.searchField,
    super.key,
  });

  static const double height = 52;

  final String title;
  final bool showBackButton;
  final VoidCallback onBack;
  final bool isLoading;
  final VoidCallback onRefresh;
  final VoidCallback? onOpenShortcuts;
  final Widget? searchField;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: height,
      child: Stack(
        children: <Widget>[
          const Positioned.fill(child: _DragToMoveSurface()),
          Positioned.fill(
            child: Row(
              children: <Widget>[
                // 左侧：返回 + 页面标题，占据等宽弹性区。
                Expanded(
                  child: Row(
                    children: <Widget>[
                      const SizedBox(width: 16),
                      _AnimatedBackButton(
                        visible: showBackButton,
                        onBack: onBack,
                      ),
                      Flexible(child: _AnimatedPageTitle(title: title)),
                    ],
                  ),
                ),
                // 中间：搜索框。两侧等宽弹性区使其始终居中。
                if (searchField != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: searchField!,
                  ),
                // 右侧：操作按钮 + 窗口控制，靠右对齐。
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      if (onOpenShortcuts != null) ...<Widget>[
                        _HoverIconButton(
                          icon: Icons.keyboard_rounded,
                          tooltip: '键盘快捷键',
                          foreground: colorScheme.onSurface,
                          onTap: onOpenShortcuts,
                        ),
                        const SizedBox(width: 8),
                      ],
                      _RefreshButton(
                        isLoading: isLoading,
                        onRefresh: onRefresh,
                      ),
                      const SizedBox(width: 10),
                      const DesktopWindowControls(),
                      const SizedBox(width: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            // 空闲时卸载进度条，避免透明动画空跑。
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              child: isLoading
                  ? const LinearProgressIndicator(
                      key: ValueKey<bool>(true),
                      minHeight: 2,
                      backgroundColor: Colors.transparent,
                    )
                  : const SizedBox(height: 2, key: ValueKey<bool>(false)),
            ),
          ),
        ],
      ),
    );
  }
}

class _DragToMoveSurface extends StatelessWidget {
  const _DragToMoveSurface();

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: _toggleMaximize,
    );
  }
}

class _AnimatedBackButton extends StatelessWidget {
  const _AnimatedBackButton({required this.visible, required this.onBack});

  final bool visible;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      alignment: Alignment.centerLeft,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        offset: visible ? Offset.zero : const Offset(-0.3, 0),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: visible ? 1 : 0,
          child: visible
              ? Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _HoverIconButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: '返回 (Alt+←)',
                    foreground: colorScheme.onSurface,
                    onTap: onBack,
                  ),
                )
              : const SizedBox(height: 32),
        ),
      ),
    );
  }
}

class _AnimatedPageTitle extends StatelessWidget {
  const _AnimatedPageTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Align(
        alignment: Alignment.centerLeft,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
            return Stack(
              alignment: Alignment.centerLeft,
              children: <Widget>[
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            );
          },
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.45),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: Text(
            title,
            key: ValueKey<String>(title),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              color: colorScheme.onSurface.withValues(alpha: 0.85),
            ),
          ),
        ),
      ),
    );
  }
}

class _RefreshButton extends StatefulWidget {
  const _RefreshButton({required this.isLoading, required this.onRefresh});

  final bool isLoading;
  final VoidCallback onRefresh;

  @override
  State<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<_RefreshButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spinController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isLoading) {
      _spinController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _RefreshButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isLoading == oldWidget.isLoading) {
      return;
    }
    if (widget.isLoading) {
      _spinController.repeat();
    } else {
      _spinController.animateTo(
        1,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return _HoverIconButton(
      icon: Icons.refresh_rounded,
      tooltip: '刷新 (F5)',
      foreground: colorScheme.primary,
      onTap: widget.isLoading ? null : widget.onRefresh,
      iconBuilder: (Widget icon) {
        return RotationTransition(turns: _spinController, child: icon);
      },
    );
  }
}

class _HoverIconButton extends StatefulWidget {
  const _HoverIconButton({
    required this.icon,
    required this.tooltip,
    required this.foreground,
    required this.onTap,
    this.iconBuilder,
  });

  final IconData icon;
  final String tooltip;
  final Color foreground;
  final VoidCallback? onTap;
  final Widget Function(Widget icon)? iconBuilder;

  @override
  State<_HoverIconButton> createState() => _HoverIconButtonState();
}

class _HoverIconButtonState extends State<_HoverIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool enabled = widget.onTap != null;
    Widget icon = Icon(
      widget.icon,
      size: 18,
      color: widget.foreground.withValues(alpha: enabled ? 1 : 0.55),
    );
    if (widget.iconBuilder != null) {
      icon = widget.iconBuilder!(icon);
    }

    return Tooltip(
      message: widget.tooltip,
      excludeFromSemantics: true,
      waitDuration: const Duration(milliseconds: 600),
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            scale: _isHovered && enabled ? 1.08 : 1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _isHovered && enabled
                    ? colorScheme.onSurface.withValues(alpha: 0.07)
                    : colorScheme.surfaceContainerLow.withValues(alpha: 0.45),
                shape: BoxShape.circle,
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(
                    alpha: _isHovered && enabled ? 0.6 : 0.35,
                  ),
                ),
              ),
              child: Center(child: icon),
            ),
          ),
        ),
      ),
    );
  }
}
