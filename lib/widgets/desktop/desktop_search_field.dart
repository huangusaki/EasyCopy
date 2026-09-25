import 'package:flutter/material.dart';
import 'package:reader/widgets/search_history_panel.dart';

class DesktopSearchField extends StatefulWidget {
  const DesktopSearchField({
    required this.controller,
    required this.history,
    required this.onSubmit,
    required this.onRemoveHistoryEntry,
    required this.onClearHistory,
    this.focusNode,
    super.key,
  });

  final TextEditingController controller;
  final List<String> history;
  final ValueChanged<String> onSubmit;
  final ValueChanged<String> onRemoveHistoryEntry;
  final VoidCallback onClearHistory;
  final FocusNode? focusNode;

  @override
  State<DesktopSearchField> createState() => _DesktopSearchFieldState();
}

class _DesktopSearchFieldState extends State<DesktopSearchField> {
  static const double _idleWidth = 232;
  static const double _focusedWidth = 332;
  static const Object _tapRegionGroup = 'desktop-search-field';

  final LayerLink _layerLink = LayerLink();
  final GlobalKey _flyoutKey = GlobalKey();
  final OverlayPortalController _flyoutController = OverlayPortalController();

  late FocusNode _focusNode;
  bool _ownsFocusNode = false;
  bool _isHovered = false;

  bool get _isFocused => _focusNode.hasFocus;

  @override
  void initState() {
    super.initState();
    _adoptFocusNode();
  }

  @override
  void didUpdateWidget(covariant DesktopSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _disposeFocusNode();
      _adoptFocusNode();
    }
    // 避免在 build 阶段触碰 OverlayPortal。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncFlyoutVisibility();
      }
    });
  }

  @override
  void dispose() {
    _disposeFocusNode();
    super.dispose();
  }

  void _adoptFocusNode() {
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode(debugLabel: 'desktop-search');
    _focusNode.addListener(_handleFocusChanged);
  }

  void _disposeFocusNode() {
    _focusNode.removeListener(_handleFocusChanged);
    if (_ownsFocusNode) {
      _focusNode.dispose();
    }
  }

  void _handleFocusChanged() {
    if (!mounted) {
      return;
    }
    setState(_syncFlyoutVisibility);
  }

  void _syncFlyoutVisibility() {
    final bool shouldShow = _isFocused && widget.history.isNotEmpty;
    if (shouldShow && !_flyoutController.isShowing) {
      _flyoutController.show();
    } else if (!shouldShow && _flyoutController.isShowing) {
      _flyoutController.hide();
    }
  }

  void _submit(String value) {
    final String query = value.trim();
    if (query.isEmpty) {
      return;
    }
    widget.onSubmit(query);
    _focusNode.unfocus();
  }

  void _handleTapOutside(PointerDownEvent event) {
    final BuildContext? flyoutContext = _flyoutKey.currentContext;
    final RenderObject? renderObject = flyoutContext?.findRenderObject();
    if (renderObject is RenderBox && renderObject.hasSize) {
      final Rect flyoutBounds =
          renderObject.localToGlobal(Offset.zero) & renderObject.size;
      if (flyoutBounds.contains(event.position)) {
        return;
      }
    }
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool active = _isFocused || _isHovered;

    return OverlayPortal(
      controller: _flyoutController,
      overlayChildBuilder: _buildFlyout,
      child: TapRegion(
        groupId: _tapRegionGroup,
        onTapOutside: _handleTapOutside,
        child: CompositedTransformTarget(
          link: _layerLink,
          child: MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              width: _isFocused ? _focusedWidth : _idleWidth,
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow.withValues(
                  alpha: active ? 0.92 : 0.6,
                ),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: _isFocused
                      ? colorScheme.primary.withValues(alpha: 0.55)
                      : colorScheme.outlineVariant.withValues(alpha: 0.5),
                  width: _isFocused ? 1.4 : 1,
                ),
                boxShadow: <BoxShadow>[
                  if (_isFocused)
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      blurRadius: 18,
                      offset: const Offset(0, 4),
                    ),
                ],
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: _isFocused
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _focusNode,
                      onTapOutside: _handleTapOutside,
                      onSubmitted: _submit,
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: const InputDecoration(
                        hintText: '搜索漫画、作者或题材',
                        hintStyle: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                        isCollapsed: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: widget.controller,
                    builder:
                        (
                          BuildContext context,
                          TextEditingValue value,
                          Widget? _,
                        ) {
                          if (value.text.isEmpty) {
                            return const SizedBox.shrink();
                          }
                          return _RoundIconButton(
                            icon: Icons.close_rounded,
                            tooltip: '清空',
                            onTap: () {
                              widget.controller.clear();
                              _focusNode.requestFocus();
                            },
                          );
                        },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFlyout(BuildContext context) {
    return Positioned(
      width: _focusedWidth,
      // ExcludeSemantics 必须在 Follower 内侧，否则 hitTest 会落回原点。
      child: CompositedTransformFollower(
        link: _layerLink,
        targetAnchor: Alignment.bottomLeft,
        followerAnchor: Alignment.topLeft,
        offset: const Offset(0, 8),
        showWhenUnlinked: false,
        child: ExcludeSemantics(
          child: TapRegion(
            key: _flyoutKey,
            groupId: _tapRegionGroup,
            child: TextFieldTapRegion(
              child: SearchHistoryPanel(
                history: widget.history,
                onSelect: _submit,
                onRemove: widget.onRemoveHistoryEntry,
                onClear: () {
                  _focusNode.unfocus();
                  widget.onClearHistory();
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Icon(
            icon,
            size: 15,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
