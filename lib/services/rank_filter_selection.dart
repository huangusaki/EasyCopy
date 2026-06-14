import 'package:reader/config/app_config.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/services/link_action_selection.dart';

RankPageData applyRankFilterSelection(
  RankPageData page, {
  required Uri currentUri,
  required Uri targetUri,
}) {
  final String targetRouteKey = AppConfig.routeKeyForUri(targetUri);
  final ({List<LinkAction> options, bool changed}) categoriesResult =
      selectActiveLinkByRouteKey(
        page.categories,
        currentUri: currentUri,
        targetRouteKey: targetRouteKey,
      );
  final ({List<LinkAction> options, bool changed}) periodsResult =
      selectActiveLinkByRouteKey(
        page.periods,
        currentUri: currentUri,
        targetRouteKey: targetRouteKey,
      );

  if (!categoriesResult.changed && !periodsResult.changed) {
    return page;
  }

  return RankPageData(
    title: page.title,
    uri: page.uri,
    categories: categoriesResult.options,
    periods: periodsResult.options,
    items: page.items,
  );
}
