import 'package:flutter/material.dart';
import 'package:reader/widgets/search_history_panel.dart';

class MobileSearchField extends StatefulWidget {
  const MobileSearchField({
    required this.controller,
    required this.focusNode,
    required this.navigationKey,
    required this.history,
    required this.onSubmit,
    required this.onClearQuery,
    required this.onRemoveHistoryEntry,
    required this.onClearHistory,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String navigationKey;
  final List<String> history;
  final ValueChanged<String> onSubmit;
  final VoidCallback onClearQuery;
  final ValueChanged<String> onRemoveHistoryEntry;
  final VoidCallback onClearHistory;

  @override
  State<MobileSearchField> createState() => _MobileSearchFieldState();
}

class _MobileSearchFieldState extends State<MobileSearchField>
    with WidgetsBindingObserver {
  final OverlayPortalController _overlay = OverlayPortalController();
  final Object _tapGroup = Object();
  bool _keyboardWasVisible = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_syncHistory);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(covariant MobileSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_syncHistory);
      widget.focusNode.addListener(_syncHistory);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (oldWidget.navigationKey != widget.navigationKey) {
        _dismiss();
      } else {
        _syncHistory();
      }
    });
  }

  @override
  void didChangeMetrics() {
    final bool visible = View.of(context).viewInsets.bottom > 0;
    final bool keyboardClosed = _keyboardWasVisible && !visible;
    _keyboardWasVisible = visible;
    // Android 返回可能只关闭输入法，未触发页面的返回回调。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (keyboardClosed) {
        _dismiss();
      } else if (_overlay.isShowing) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.focusNode.removeListener(_syncHistory);
    super.dispose();
  }

  void _syncHistory() {
    final bool show = widget.focusNode.hasFocus && widget.history.isNotEmpty;
    if (show && !_overlay.isShowing) {
      _overlay.show();
    } else if (!show && _overlay.isShowing) {
      _overlay.hide();
    }
  }

  void _dismiss() {
    if (_overlay.isShowing) _overlay.hide();
    widget.focusNode.unfocus();
  }

  void _submit(String value) {
    final String query = value.trim();
    if (query.isEmpty) return;
    _dismiss();
    widget.onSubmit(query);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _overlay,
      overlayChildBuilder: _buildHistory,
      child: TextFieldTapRegion(
        groupId: _tapGroup,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.search_rounded, color: colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  groupId: _tapGroup,
                  controller: widget.controller,
                  focusNode: widget.focusNode,
                  onTapOutside: (_) => _dismiss(),
                  onSubmitted: _submit,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: '搜索漫画、作者或题材',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: widget.controller,
                builder: (context, value, _) => value.text.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        tooltip: '清空输入',
                        onPressed: widget.onClearQuery,
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
              IconButton(
                tooltip: '搜索',
                onPressed: () => _submit(widget.controller.text),
                icon: const Icon(Icons.arrow_forward_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistory(BuildContext context, OverlayChildLayoutInfo layout) {
    final Rect field = MatrixUtils.transformRect(
      layout.childPaintTransform,
      Offset.zero & layout.childSize,
    );
    // Scaffold 会清除子树的 viewInsets，直接读取 View 的真实键盘边界。
    final MediaQueryData view = MediaQueryData.fromView(View.of(context));
    final double bottomInset = view.viewInsets.bottom > 0
        ? view.viewInsets.bottom
        : view.viewPadding.bottom;
    final double top = field.bottom + 8;
    final double availableHeight =
        layout.overlaySize.height - bottomInset - top - 8;
    if (availableHeight <= 0 || field.top < view.padding.top) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: field.left,
      top: top,
      width: field.width,
      child: TextFieldTapRegion(
        groupId: _tapGroup,
        child: SearchHistoryPanel(
          maxHeight: availableHeight.clamp(0, 320),
          history: widget.history,
          onSelect: _submit,
          onRemove: widget.onRemoveHistoryEntry,
          onClear: () {
            _dismiss();
            widget.onClearHistory();
          },
        ),
      ),
    );
  }
}
