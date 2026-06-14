import 'package:reader/config/app_config.dart';
import 'package:reader/models/page_models.dart';

/// 按目标 routeKey 更新选中项。
///
/// 未命中或选中态无变化时返回原列表。
({List<LinkAction> options, bool changed}) selectActiveLinkByRouteKey(
  List<LinkAction> options, {
  required Uri currentUri,
  required String targetRouteKey,
}) {
  final int selectedIndex = options.indexWhere((LinkAction option) {
    if (!option.isNavigable) {
      return false;
    }
    final Uri resolvedUri = currentUri.resolve(option.href);
    return AppConfig.routeKeyForUri(resolvedUri) == targetRouteKey;
  });
  if (selectedIndex == -1) {
    return (options: options, changed: false);
  }

  bool changed = false;
  final List<LinkAction> nextOptions = <LinkAction>[
    for (int index = 0; index < options.length; index += 1)
      if (options[index].active != (index == selectedIndex))
        (() {
          changed = true;
          return options[index].copyWith(active: index == selectedIndex);
        })()
      else
        options[index],
  ];
  if (!changed) {
    return (options: options, changed: false);
  }
  return (options: nextOptions, changed: true);
}
