import 'package:reader/config/app_config.dart';
import 'package:reader/models/page_models.dart';

/// 筛选链接来自最后一次响应，只替换点击组控制的参数，保留加载中的其他选择。
Uri resolveDiscoverFilterUri(
  DiscoverPageData page, {
  required Uri currentUri,
  required FilterGroupData group,
  required String href,
}) {
  final Uri loadedUri = Uri.parse(page.uri);
  final Uri optionUri = AppConfig.resolveNavigationUri(
    href,
    currentUri: loadedUri,
  );
  final Set<String> keys = _filterQueryKeys(group, loadedUri);
  if (keys.isNotEmpty &&
      keys.every(
        (key) =>
            optionUri.queryParameters[key] == currentUri.queryParameters[key],
      )) {
    return currentUri;
  }
  final Map<String, String> query = Map<String, String>.from(
    keys.isEmpty ? optionUri.queryParameters : currentUri.queryParameters,
  );
  for (final String key in keys) {
    if (optionUri.queryParameters.containsKey(key)) {
      query[key] = optionUri.queryParameters[key]!;
    } else {
      query.remove(key);
    }
  }
  query.remove('page');
  query.remove('offset');
  return optionUri.replace(
    query: query.isEmpty ? '' : null,
    queryParameters: query.isEmpty ? null : query,
  );
}

DiscoverPageData applyDiscoverFilterSelection(
  DiscoverPageData page, {
  required Uri currentUri,
  required Uri targetUri,
}) {
  final Uri loadedUri = Uri.parse(page.uri);
  bool didChange = false;

  final List<FilterGroupData> nextFilters = page.filters
      .map((FilterGroupData group) {
        final Set<String> keys = _filterQueryKeys(group, loadedUri);
        if (keys.isEmpty) {
          return group;
        }
        final int selectedIndex = group.options.indexWhere((option) {
          if (!option.isNavigable) return false;
          final Uri optionUri = loadedUri.resolve(option.href);
          return keys.every(
            (key) =>
                optionUri.queryParameters[key] ==
                targetUri.queryParameters[key],
          );
        });
        // 原始 URL 可能省略默认条件，未匹配的组保留服务端给出的选中态。
        if (selectedIndex == -1 ||
            group.options.indexed.every(
              (entry) => entry.$2.active == (entry.$1 == selectedIndex),
            )) {
          return group;
        }
        didChange = true;
        return group.copyWith(
          options: group.options.indexed
              .map((entry) {
                final bool active = entry.$1 == selectedIndex;
                return entry.$2.active == active
                    ? entry.$2
                    : entry.$2.copyWith(active: active);
              })
              .toList(growable: false),
        );
      })
      .toList(growable: false);

  if (!didChange) {
    return page;
  }

  // page.uri 和 href 继续代表真实响应，不用乐观条件覆盖其基准。
  return page.copyWith(filters: nextFilters);
}

Set<String> _filterQueryKeys(FilterGroupData group, Uri loadedUri) {
  final List<Map<String, String>> queries = group.options
      .where((option) => option.isNavigable)
      .map((option) => loadedUri.resolve(option.href))
      // “查看全部分类”等跨页面入口不是本组的筛选条件。
      .where((uri) => uri.path == loadedUri.path)
      .map((uri) => uri.queryParameters)
      .toList(growable: false);
  return <String>{for (final query in queries) ...query.keys}..removeWhere(
    (key) =>
        key == 'page' ||
        key == 'offset' ||
        queries.map((query) => query[key]).toSet().length < 2,
  );
}
