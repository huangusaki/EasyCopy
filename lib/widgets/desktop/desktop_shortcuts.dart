import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reader/models/shortcut_preferences.dart';

class DesktopShortcuts extends StatefulWidget {
  const DesktopShortcuts({
    required this.shortcuts,
    required this.onSelectTab,
    required this.onStepTab,
    required this.onRefresh,
    required this.onBack,
    required this.onFocusSearch,
    required this.child,
    super.key,
  });

  final ShortcutPreferences shortcuts;
  final ValueChanged<int> onSelectTab;
  final ValueChanged<int> onStepTab;
  final VoidCallback onRefresh;
  final VoidCallback onBack;
  final VoidCallback onFocusSearch;
  final Widget child;

  @override
  State<DesktopShortcuts> createState() => _DesktopShortcutsState();
}

class _DesktopShortcutsState extends State<DesktopShortcuts> {
  final FocusScopeNode _focusNode = FocusScopeNode(
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

  KeyEventResult _handleTabNavigation(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    if (keyboard.isAltPressed || keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    final bool tab = key == LogicalKeyboardKey.tab;
    final bool arrow =
        !keyboard.isControlPressed &&
        !keyboard.isShiftPressed &&
        (key == LogicalKeyboardKey.arrowLeft ||
            key == LogicalKeyboardKey.arrowRight);
    if (!tab && !arrow) {
      return KeyEventResult.ignored;
    }
    final bool editing =
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorStateOfType<EditableTextState>() !=
        null;
    if (editing && !keyboard.isControlPressed) {
      return KeyEventResult.ignored;
    }
    if (event is KeyRepeatEvent) {
      return KeyEventResult.handled;
    }
    widget.onStepTab(
      (tab && keyboard.isShiftPressed) || key == LogicalKeyboardKey.arrowLeft
          ? -1
          : 1,
    );
    _focusNode.requestFocus();
    return KeyEventResult.handled;
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
    return Focus(
      onKeyEvent: _handleTabNavigation,
      skipTraversal: true,
      includeSemantics: false,
      child: CallbackShortcuts(
        bindings: bindings,
        child: FocusScope(
          node: _focusNode,
          autofocus: true,
          skipTraversal: true,
          includeSemantics: false,
          child: widget.child,
        ),
      ),
    );
  }
}
