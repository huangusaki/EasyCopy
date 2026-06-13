import 'package:flutter/material.dart';
import 'package:reader/models/shortcut_preferences.dart';

class DesktopShortcuts extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final Map<ShortcutActivator, VoidCallback> bindings =
        <ShortcutActivator, VoidCallback>{
          shortcuts.bindingFor(ShortcutAction.switchTab1).activator: () =>
              onSelectTab(0),
          shortcuts.bindingFor(ShortcutAction.switchTab2).activator: () =>
              onSelectTab(1),
          shortcuts.bindingFor(ShortcutAction.switchTab3).activator: () =>
              onSelectTab(2),
          shortcuts.bindingFor(ShortcutAction.switchTab4).activator: () =>
              onSelectTab(3),
          shortcuts.bindingFor(ShortcutAction.refreshPage).activator: onRefresh,
          shortcuts.bindingFor(ShortcutAction.navigateBack).activator: onBack,
          shortcuts.bindingFor(ShortcutAction.focusSearch).activator:
              onFocusSearch,
        };
    return CallbackShortcuts(
      bindings: bindings,
      child: Focus(
        autofocus: true,
        skipTraversal: true,
        includeSemantics: false,
        child: child,
      ),
    );
  }
}
