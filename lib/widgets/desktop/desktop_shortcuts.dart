import 'package:flutter/material.dart';
import 'package:reader/models/shortcut_preferences.dart';

class DesktopShortcuts extends StatefulWidget {
  const DesktopShortcuts({
    required this.shortcuts,
    required this.onSelectTab,
    required this.onRefresh,
    required this.onBack,
    required this.onFocusSearch,
    required this.child,
    super.key,
  });

  final ShortcutPreferences shortcuts;
  final ValueChanged<int> onSelectTab;
  final VoidCallback onRefresh;
  final VoidCallback onBack;
  final VoidCallback onFocusSearch;
  final Widget child;

  @override
  State<DesktopShortcuts> createState() => _DesktopShortcutsState();
}

class _DesktopShortcutsState extends State<DesktopShortcuts> {
  final FocusNode _focusNode = FocusNode(
    debugLabel: 'desktop-global-shortcuts',
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _focusNode.canRequestFocus) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Map<ShortcutActivator, VoidCallback>
    bindings = <ShortcutActivator, VoidCallback>{
      widget.shortcuts.bindingFor(ShortcutAction.switchTab1).activator: () =>
          widget.onSelectTab(0),
      widget.shortcuts.bindingFor(ShortcutAction.switchTab2).activator: () =>
          widget.onSelectTab(1),
      widget.shortcuts.bindingFor(ShortcutAction.switchTab3).activator: () =>
          widget.onSelectTab(2),
      widget.shortcuts.bindingFor(ShortcutAction.switchTab4).activator: () =>
          widget.onSelectTab(3),
      widget.shortcuts.bindingFor(ShortcutAction.refreshPage).activator:
          widget.onRefresh,
      widget.shortcuts.bindingFor(ShortcutAction.navigateBack).activator:
          widget.onBack,
      widget.shortcuts.bindingFor(ShortcutAction.focusSearch).activator:
          widget.onFocusSearch,
    };
    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(
        focusNode: _focusNode,
        autofocus: true,
        skipTraversal: true,
        includeSemantics: false,
        child: widget.child,
      ),
    );
  }
}
