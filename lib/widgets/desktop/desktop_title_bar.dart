import 'package:flutter/material.dart';
import 'package:reader/widgets/desktop/desktop_window_controls.dart';
import 'package:window_manager/window_manager.dart';

class DesktopTitleBar extends StatelessWidget {
  const DesktopTitleBar({
    required this.showBackButton,
    required this.onBack,
    required this.isLoading,
    required this.onRefresh,
    this.onOpenShortcuts,
    this.searchField,
    super.key,
  });

  static const double height = 52;

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
                // 左侧：返回按钮，占据等宽弹性区（和右侧对称，使搜索框居中）。
                Expanded(
                  child: Row(
                    children: <Widget>[
                      const SizedBox(width: 16),
                      _AnimatedBackButton(
                        visible: showBackButton,
                        onBack: onBack,
                      ),
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
                        DesktopTitleBarButton(
                          icon: Icons.keyboard_rounded,
                          iconSize: 18,
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: toggleDesktopMaximize,
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
                  child: DesktopTitleBarButton(
                    icon: Icons.arrow_back_rounded,
                    iconSize: 18,
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
    return DesktopTitleBarButton(
      icon: Icons.refresh_rounded,
      iconSize: 18,
      tooltip: '刷新 (F5)',
      foreground: colorScheme.primary,
      onTap: widget.isLoading ? null : widget.onRefresh,
      iconBuilder: (Widget icon) {
        return RotationTransition(turns: _spinController, child: icon);
      },
    );
  }
}
