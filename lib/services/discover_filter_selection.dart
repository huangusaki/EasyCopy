import 'package:reader/config/app_config.dart';
import 'package:reader/models/page_models.dart';

DiscoverPageData applyDiscoverFilterSelection(
  DiscoverPageData page, {
  required Uri currentUri,
  required Uri targetUri,
}) {
  final String targetRouteKey = AppConfig.routeKeyForUri(targetUri);
  bool didChange = false;

  final List<FilterGroupData> nextFilters = page.filters
      .map((FilterGroupData group) {
        final int selectedIndex = group.options.indexWhere((LinkAction option) {
          if (!option.isNavigable) {
            return false;
          }
          final Uri resolvedUri = currentUri.resolve(option.href);
          return AppConfig.routeKeyForUri(resolvedUri) == targetRouteKey;
        });
        if (selectedIndex == -1) {
          return group;
        }

        bool groupChanged = false;
        final List<LinkAction> nextOptions = <LinkAction>[
          for (int index = 0; index < group.options.length; index += 1)
            if (group.options[index].active != (index == selectedIndex))
              (() {
                groupChanged = true;
                return group.options[index].copyWith(
                  active: index == selectedIndex,
                );
              })()
            else
              group.options[index],
        ];

        if (!groupChanged) {
          return group;
        }

        didChange = true;
        return group.copyWith(options: nextOptions);
      })
      .toList(growable: false);

  if (!didChange) {
    return page;
  }

  return page.copyWith(filters: nextFilters);
}
