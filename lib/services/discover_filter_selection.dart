import 'package:reader/config/app_config.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/services/link_action_selection.dart';

DiscoverPageData applyDiscoverFilterSelection(
  DiscoverPageData page, {
  required Uri currentUri,
  required Uri targetUri,
}) {
  final String targetRouteKey = AppConfig.routeKeyForUri(targetUri);
  bool didChange = false;

  final List<FilterGroupData> nextFilters = page.filters
      .map((FilterGroupData group) {
        final ({List<LinkAction> options, bool changed}) result =
            selectActiveLinkByRouteKey(
              group.options,
              currentUri: currentUri,
              targetRouteKey: targetRouteKey,
            );
        if (!result.changed) {
          return group;
        }
        didChange = true;
        return group.copyWith(options: result.options);
      })
      .toList(growable: false);

  if (!didChange) {
    return page;
  }

  return page.copyWith(filters: nextFilters);
}
