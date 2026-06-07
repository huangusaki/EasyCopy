import 'package:reader/config/app_config.dart';
import 'package:reader/models/page_models.dart';

RankPageData applyRankFilterSelection(
  RankPageData page, {
  required Uri currentUri,
  required Uri targetUri,
}) {
  final String targetRouteKey = AppConfig.routeKeyForUri(targetUri);
  bool didChange = false;

  List<LinkAction> updateOptions(List<LinkAction> options) {
    final int selectedIndex = options.indexWhere((LinkAction option) {
      if (!option.isNavigable) {
        return false;
      }
      final Uri resolvedUri = currentUri.resolve(option.href);
      return AppConfig.routeKeyForUri(resolvedUri) == targetRouteKey;
    });
    if (selectedIndex == -1) {
      return options;
    }

    bool groupChanged = false;
    final List<LinkAction> nextOptions = <LinkAction>[
      for (int index = 0; index < options.length; index += 1)
        if (options[index].active != (index == selectedIndex))
          (() {
            groupChanged = true;
            return options[index].copyWith(active: index == selectedIndex);
          })()
        else
          options[index],
    ];

    if (groupChanged) {
      didChange = true;
    }
    return nextOptions;
  }

  final List<LinkAction> nextCategories = updateOptions(page.categories);
  final List<LinkAction> nextPeriods = updateOptions(page.periods);

  if (!didChange) {
    return page;
  }

  return RankPageData(
    title: page.title,
    uri: page.uri,
    categories: nextCategories,
    periods: nextPeriods,
    items: page.items,
  );
}
