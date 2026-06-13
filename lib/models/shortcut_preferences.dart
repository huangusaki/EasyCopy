import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// name 已持久化，只可新增。
enum ShortcutAction {
  switchTab1,
  switchTab2,
  switchTab3,
  switchTab4,
  refreshPage,
  navigateBack,
  focusSearch,
  exitReader,
  readerPreviousPage,
  readerNextPage,
  readerScrollUp,
  readerScrollDown,
  readerPreviousChapter,
  readerNextChapter,
  readerToggleFullscreen,
}

enum ShortcutScope { global, reader }

extension ShortcutActionMeta on ShortcutAction {
  String get label => switch (this) {
    ShortcutAction.switchTab1 => '切换到「首页」',
    ShortcutAction.switchTab2 => '切换到「发现」',
    ShortcutAction.switchTab3 => '切换到「排行」',
    ShortcutAction.switchTab4 => '切换到「我的」',
    ShortcutAction.refreshPage => '刷新当前页',
    ShortcutAction.navigateBack => '返回上一页',
    ShortcutAction.focusSearch => '聚焦搜索框',
    ShortcutAction.exitReader => '退出阅读器',
    ShortcutAction.readerPreviousPage => '上一页',
    ShortcutAction.readerNextPage => '下一页',
    ShortcutAction.readerScrollUp => '向上滚动页面',
    ShortcutAction.readerScrollDown => '向下滚动页面',
    ShortcutAction.readerPreviousChapter => '上一章',
    ShortcutAction.readerNextChapter => '下一章',
    ShortcutAction.readerToggleFullscreen => '切换全屏',
  };

  ShortcutScope get scope => switch (this) {
    ShortcutAction.exitReader ||
    ShortcutAction.readerPreviousPage ||
    ShortcutAction.readerNextPage ||
    ShortcutAction.readerScrollUp ||
    ShortcutAction.readerScrollDown ||
    ShortcutAction.readerPreviousChapter ||
    ShortcutAction.readerNextChapter ||
    ShortcutAction.readerToggleFullscreen => ShortcutScope.reader,
    _ => ShortcutScope.global,
  };

  ShortcutBinding get defaultBinding => switch (this) {
    ShortcutAction.switchTab1 => ShortcutBinding(
      keyId: LogicalKeyboardKey.digit1.keyId,
      control: true,
    ),
    ShortcutAction.switchTab2 => ShortcutBinding(
      keyId: LogicalKeyboardKey.digit2.keyId,
      control: true,
    ),
    ShortcutAction.switchTab3 => ShortcutBinding(
      keyId: LogicalKeyboardKey.digit3.keyId,
      control: true,
    ),
    ShortcutAction.switchTab4 => ShortcutBinding(
      keyId: LogicalKeyboardKey.digit4.keyId,
      control: true,
    ),
    ShortcutAction.refreshPage => ShortcutBinding(
      keyId: LogicalKeyboardKey.f5.keyId,
    ),
    ShortcutAction.navigateBack => ShortcutBinding(
      keyId: LogicalKeyboardKey.arrowLeft.keyId,
      alt: true,
    ),
    ShortcutAction.focusSearch => ShortcutBinding(
      keyId: LogicalKeyboardKey.keyK.keyId,
      control: true,
    ),
    ShortcutAction.exitReader => ShortcutBinding(
      keyId: LogicalKeyboardKey.escape.keyId,
    ),
    ShortcutAction.readerPreviousPage => ShortcutBinding(
      keyId: LogicalKeyboardKey.arrowLeft.keyId,
    ),
    ShortcutAction.readerNextPage => ShortcutBinding(
      keyId: LogicalKeyboardKey.arrowRight.keyId,
    ),
    ShortcutAction.readerScrollUp => ShortcutBinding(
      keyId: LogicalKeyboardKey.arrowUp.keyId,
    ),
    ShortcutAction.readerScrollDown => ShortcutBinding(
      keyId: LogicalKeyboardKey.arrowDown.keyId,
    ),
    ShortcutAction.readerPreviousChapter => ShortcutBinding(
      keyId: LogicalKeyboardKey.pageUp.keyId,
    ),
    ShortcutAction.readerNextChapter => ShortcutBinding(
      keyId: LogicalKeyboardKey.pageDown.keyId,
    ),
    ShortcutAction.readerToggleFullscreen => ShortcutBinding(
      keyId: LogicalKeyboardKey.f11.keyId,
    ),
  };
}

String shortcutScopeLabel(ShortcutScope scope) => switch (scope) {
  ShortcutScope.global => '全局',
  ShortcutScope.reader => '阅读器',
};

@immutable
class ShortcutBinding {
  const ShortcutBinding({
    required this.keyId,
    this.control = false,
    this.alt = false,
    this.shift = false,
    this.meta = false,
  });

  factory ShortcutBinding.fromJson(Map<String, Object?> json) {
    return ShortcutBinding(
      keyId: (json['keyId'] as num?)?.toInt() ?? 0,
      control: (json['control'] as bool?) ?? false,
      alt: (json['alt'] as bool?) ?? false,
      shift: (json['shift'] as bool?) ?? false,
      meta: (json['meta'] as bool?) ?? false,
    );
  }

  final int keyId;
  final bool control;
  final bool alt;
  final bool shift;
  final bool meta;

  bool get isValid => keyId != 0;

  LogicalKeyboardKey get key => LogicalKeyboardKey(keyId);

  SingleActivator get activator => SingleActivator(
    key,
    control: control,
    alt: alt,
    shift: shift,
    meta: meta,
  );

  String get label {
    final List<String> parts = <String>[
      if (control) 'Ctrl',
      if (alt) 'Alt',
      if (shift) 'Shift',
      if (meta) 'Win',
      _keyLabel(key),
    ];
    return parts.join(' + ');
  }

  static String _keyLabel(LogicalKeyboardKey key) {
    final String? mapped = _specialLabels[key.keyId];
    if (mapped != null) {
      return mapped;
    }
    final String keyLabel = key.keyLabel;
    if (keyLabel.isNotEmpty) {
      return keyLabel.toUpperCase();
    }
    return key.debugName ?? 'Key(${key.keyId})';
  }

  static final Map<int, String> _specialLabels = <int, String>{
    LogicalKeyboardKey.arrowLeft.keyId: '←',
    LogicalKeyboardKey.arrowRight.keyId: '→',
    LogicalKeyboardKey.arrowUp.keyId: '↑',
    LogicalKeyboardKey.arrowDown.keyId: '↓',
    LogicalKeyboardKey.escape.keyId: 'Esc',
    LogicalKeyboardKey.enter.keyId: 'Enter',
    LogicalKeyboardKey.space.keyId: 'Space',
    LogicalKeyboardKey.tab.keyId: 'Tab',
    LogicalKeyboardKey.backspace.keyId: 'Backspace',
    LogicalKeyboardKey.delete.keyId: 'Delete',
    LogicalKeyboardKey.home.keyId: 'Home',
    LogicalKeyboardKey.end.keyId: 'End',
    LogicalKeyboardKey.pageUp.keyId: 'PageUp',
    LogicalKeyboardKey.pageDown.keyId: 'PageDown',
  };

  bool isSameChord(ShortcutBinding other) {
    return keyId == other.keyId &&
        control == other.control &&
        alt == other.alt &&
        shift == other.shift &&
        meta == other.meta;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'keyId': keyId,
    'control': control,
    'alt': alt,
    'shift': shift,
    'meta': meta,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ShortcutBinding && isSameChord(other);
  }

  @override
  int get hashCode => Object.hash(keyId, control, alt, shift, meta);
}

@immutable
class ShortcutPreferences {
  const ShortcutPreferences({
    this.overrides = const <ShortcutAction, ShortcutBinding>{},
  });

  factory ShortcutPreferences.fromJson(Map<String, Object?> json) {
    final Object? rawOverrides = json['overrides'];
    if (rawOverrides is! Map<Object?, Object?>) {
      return const ShortcutPreferences();
    }
    final Map<ShortcutAction, ShortcutBinding> parsed =
        <ShortcutAction, ShortcutBinding>{};
    for (final MapEntry<Object?, Object?> entry in rawOverrides.entries) {
      final ShortcutAction? action = _actionByName(entry.key?.toString());
      final Object? value = entry.value;
      if (action == null || value is! Map<Object?, Object?>) {
        continue;
      }
      final ShortcutBinding binding = ShortcutBinding.fromJson(
        value.map(
          (Object? key, Object? v) =>
              MapEntry<String, Object?>(key.toString(), v),
        ),
      );
      if (binding.isValid) {
        parsed[action] = binding;
      }
    }
    return ShortcutPreferences(overrides: parsed);
  }

  final Map<ShortcutAction, ShortcutBinding> overrides;

  static ShortcutAction? _actionByName(String? name) {
    if (name == null) {
      return null;
    }
    for (final ShortcutAction action in ShortcutAction.values) {
      if (action.name == name) {
        return action;
      }
    }
    return null;
  }

  ShortcutBinding bindingFor(ShortcutAction action) =>
      overrides[action] ?? action.defaultBinding;

  bool isDefault(ShortcutAction action) => !overrides.containsKey(action);

  ShortcutAction? conflictFor(
    ShortcutBinding binding, {
    required ShortcutAction exclude,
  }) {
    for (final ShortcutAction action in ShortcutAction.values) {
      if (action == exclude) {
        continue;
      }
      if (bindingFor(action).isSameChord(binding)) {
        return action;
      }
    }
    return null;
  }

  ShortcutPreferences withBinding(
    ShortcutAction action,
    ShortcutBinding binding,
  ) {
    final Map<ShortcutAction, ShortcutBinding> next =
        Map<ShortcutAction, ShortcutBinding>.of(overrides);
    if (binding.isSameChord(action.defaultBinding)) {
      next.remove(action);
    } else {
      next[action] = binding;
    }
    return ShortcutPreferences(overrides: next);
  }

  ShortcutPreferences resetBinding(ShortcutAction action) {
    if (!overrides.containsKey(action)) {
      return this;
    }
    final Map<ShortcutAction, ShortcutBinding> next =
        Map<ShortcutAction, ShortcutBinding>.of(overrides)..remove(action);
    return ShortcutPreferences(overrides: next);
  }

  ShortcutPreferences resetAll() => const ShortcutPreferences();

  Map<String, Object?> toJson() => <String, Object?>{
    'overrides': <String, Object?>{
      for (final MapEntry<ShortcutAction, ShortcutBinding> entry
          in overrides.entries)
        entry.key.name: entry.value.toJson(),
    },
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ShortcutPreferences &&
        mapEquals(other.overrides, overrides);
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
    for (final ShortcutAction action in ShortcutAction.values)
      if (overrides.containsKey(action)) ...<Object?>[
        action,
        overrides[action],
      ],
  ]);
}
