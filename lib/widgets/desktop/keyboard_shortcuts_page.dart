import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reader/models/shortcut_preferences.dart';
import 'package:reader/services/app_preferences_controller.dart';
import 'package:reader/widgets/responsive_layout.dart';

class KeyboardShortcutsPage extends StatelessWidget {
  const KeyboardShortcutsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final AppPreferencesController controller =
        AppPreferencesController.instance;
    return Scaffold(
      backgroundColor: opaquePageBackground(context),
      appBar: AppBar(
        title: const Text('键盘快捷键'),
        actions: <Widget>[
          AnimatedBuilder(
            animation: controller,
            builder: (BuildContext context, Widget? _) {
              final bool hasOverrides =
                  controller.shortcutPreferences.overrides.isNotEmpty;
              return TextButton(
                onPressed: hasOverrides
                    ? () => _confirmResetAll(context, controller)
                    : null,
                child: const Text('全部恢复默认'),
              );
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: controller,
        builder: (BuildContext context, Widget? _) {
          final ShortcutPreferences prefs = controller.shortcutPreferences;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: <Widget>[
              for (final ShortcutScope scope in ShortcutScope.values)
                _buildScopeSection(context, controller, prefs, scope),
            ],
          );
        },
      ),
    );
  }

  Widget _buildScopeSection(
    BuildContext context,
    AppPreferencesController controller,
    ShortcutPreferences prefs,
    ShortcutScope scope,
  ) {
    final List<ShortcutAction> actions = ShortcutAction.values
        .where((ShortcutAction action) => action.scope == scope)
        .toList(growable: false);
    if (actions.isEmpty) {
      return const SizedBox.shrink();
    }
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              shortcutScopeLabel(scope),
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.72),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              children: <Widget>[
                for (int i = 0; i < actions.length; i += 1) ...<Widget>[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: 18,
                      endIndent: 18,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  _ShortcutRow(
                    action: actions[i],
                    binding: prefs.bindingFor(actions[i]),
                    isDefault: prefs.isDefault(actions[i]),
                    onEdit: () => _editBinding(context, controller, actions[i]),
                    onReset: prefs.isDefault(actions[i])
                        ? null
                        : () => controller.updateShortcutPreferences(
                            (ShortcutPreferences current) =>
                                current.resetBinding(actions[i]),
                          ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editBinding(
    BuildContext context,
    AppPreferencesController controller,
    ShortcutAction action,
  ) async {
    final ShortcutBinding? result = await showDialog<ShortcutBinding>(
      context: context,
      builder: (BuildContext context) => _ShortcutRecorderDialog(
        action: action,
        preferences: controller.shortcutPreferences,
      ),
    );
    if (result == null) {
      return;
    }
    await controller.updateShortcutPreferences(
      (ShortcutPreferences current) => current.withBinding(action, result),
    );
  }

  Future<void> _confirmResetAll(
    BuildContext context,
    AppPreferencesController controller,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('恢复默认快捷键'),
          content: const Text('将清除所有自定义绑定，恢复为出厂默认。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('恢复默认'),
            ),
          ],
        );
      },
    );
    if (confirmed ?? false) {
      await controller.updateShortcutPreferences(
        (ShortcutPreferences current) => current.resetAll(),
      );
    }
  }
}

class _ShortcutRow extends StatelessWidget {
  const _ShortcutRow({
    required this.action,
    required this.binding,
    required this.isDefault,
    required this.onEdit,
    this.onReset,
  });

  final ShortcutAction action;
  final ShortcutBinding binding;
  final bool isDefault;
  final VoidCallback onEdit;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 12, 12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                action.label,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            _ChordChip(label: binding.label),
            IconButton(
              tooltip: '恢复默认',
              onPressed: onReset,
              icon: const Icon(Icons.settings_backup_restore_rounded, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChordChip extends StatelessWidget {
  const _ChordChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w700,
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _ShortcutRecorderDialog extends StatefulWidget {
  const _ShortcutRecorderDialog({
    required this.action,
    required this.preferences,
  });

  final ShortcutAction action;
  final ShortcutPreferences preferences;

  @override
  State<_ShortcutRecorderDialog> createState() =>
      _ShortcutRecorderDialogState();
}

class _ShortcutRecorderDialogState extends State<_ShortcutRecorderDialog> {
  static final Set<int> _modifierKeyIds = <int>{
    LogicalKeyboardKey.controlLeft.keyId,
    LogicalKeyboardKey.controlRight.keyId,
    LogicalKeyboardKey.control.keyId,
    LogicalKeyboardKey.altLeft.keyId,
    LogicalKeyboardKey.altRight.keyId,
    LogicalKeyboardKey.alt.keyId,
    LogicalKeyboardKey.shiftLeft.keyId,
    LogicalKeyboardKey.shiftRight.keyId,
    LogicalKeyboardKey.shift.keyId,
    LogicalKeyboardKey.metaLeft.keyId,
    LogicalKeyboardKey.metaRight.keyId,
    LogicalKeyboardKey.meta.keyId,
  };

  ShortcutBinding? _captured;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.handled;
    }
    final LogicalKeyboardKey key = event.logicalKey;
    if (_modifierKeyIds.contains(key.keyId)) {
      return KeyEventResult.handled;
    }
    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    setState(() {
      _captured = ShortcutBinding(
        keyId: key.keyId,
        control: keyboard.isControlPressed,
        alt: keyboard.isAltPressed,
        shift: keyboard.isShiftPressed,
        meta: keyboard.isMetaPressed,
      );
    });
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final ShortcutBinding? captured = _captured;
    final ShortcutAction? conflict = captured == null
        ? null
        : widget.preferences.conflictFor(captured, exclude: widget.action);
    final bool canSave = captured != null && conflict == null;

    return AlertDialog(
      title: Text('设置「${widget.action.label}」'),
      content: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '请按下新的快捷键组合',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: conflict != null
                      ? colorScheme.error
                      : colorScheme.primary.withValues(alpha: 0.5),
                  width: 1.4,
                ),
              ),
              child: Text(
                captured?.label ?? '等待输入…',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: captured == null
                      ? colorScheme.onSurface.withValues(alpha: 0.4)
                      : colorScheme.onSurface,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ),
            if (conflict != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                '与「${conflict.label}」冲突，请换一个组合。',
                style: TextStyle(color: colorScheme.error, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: canSave
              ? () => Navigator.of(context).pop(captured)
              : null,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
