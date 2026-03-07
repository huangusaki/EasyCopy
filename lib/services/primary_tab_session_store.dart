import 'package:easy_copy/config/app_config.dart';
import 'package:easy_copy/models/page_models.dart';
import 'package:flutter/foundation.dart';

enum NavigationIntent { push, preserve, resetToRoot }

Uri _normalizeSessionUri(Uri uri) {
  final Uri rewrittenUri = AppConfig.rewriteToCurrentHost(uri);
  final List<MapEntry<String, String>> sortedEntries =
      rewrittenUri.queryParameters.entries.toList(growable: false)..sort(
        (MapEntry<String, String> left, MapEntry<String, String> right) =>
            left.key.compareTo(right.key),
      );
  return rewrittenUri.replace(
    path: rewrittenUri.path.isEmpty ? '/' : rewrittenUri.path,
    queryParameters: sortedEntries.isEmpty
        ? null
        : Map<String, String>.fromEntries(sortedEntries),
  );
}

@immutable
class PrimaryTabRouteEntry {
  const PrimaryTabRouteEntry({
    required this.uri,
    required this.routeKey,
    this.page,
    this.isLoading = false,
    this.errorMessage,
    this.standardScrollOffset = 0,
  });

  factory PrimaryTabRouteEntry.root(Uri uri) {
    final Uri normalizedUri = _normalizeSessionUri(uri);
    return PrimaryTabRouteEntry(
      uri: normalizedUri,
      routeKey: AppConfig.routeKeyForUri(normalizedUri),
    );
  }

  final Uri uri;
  final String routeKey;
  final EasyCopyPage? page;
  final bool isLoading;
  final String? errorMessage;
  final double standardScrollOffset;

  PrimaryTabRouteEntry copyWith({
    Uri? uri,
    String? routeKey,
    EasyCopyPage? page,
    bool clearPage = false,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    double? standardScrollOffset,
  }) {
    final Uri nextUri = _normalizeSessionUri(uri ?? this.uri);
    return PrimaryTabRouteEntry(
      uri: nextUri,
      routeKey: routeKey ?? AppConfig.routeKeyForUri(nextUri),
      page: clearPage ? null : (page ?? this.page),
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      standardScrollOffset: standardScrollOffset ?? this.standardScrollOffset,
    );
  }
}

class PrimaryTabSessionStore {
  PrimaryTabSessionStore({required Map<int, Uri> rootUris})
    : _rootUris = Map<int, Uri>.unmodifiable(
        rootUris.map(
          (int key, Uri value) => MapEntry(key, _normalizeSessionUri(value)),
        ),
      ),
      _stacks = <int, List<PrimaryTabRouteEntry>>{
        for (final MapEntry<int, Uri> entry in rootUris.entries)
          entry.key: <PrimaryTabRouteEntry>[
            PrimaryTabRouteEntry.root(entry.value),
          ],
      };

  final Map<int, Uri> _rootUris;
  final Map<int, List<PrimaryTabRouteEntry>> _stacks;

  PrimaryTabRouteEntry currentEntry(int tabIndex) {
    return _stackFor(tabIndex).last;
  }

  bool canPop(int tabIndex) {
    return _stackFor(tabIndex).length > 1;
  }

  void push(int tabIndex, Uri uri) {
    final List<PrimaryTabRouteEntry> stack = _stackFor(tabIndex);
    final PrimaryTabRouteEntry nextEntry = PrimaryTabRouteEntry.root(uri);
    if (_sameRoute(stack.last.uri, nextEntry.uri)) {
      stack[stack.length - 1] = stack.last.copyWith(
        uri: nextEntry.uri,
        routeKey: nextEntry.routeKey,
      );
      return;
    }
    stack.add(nextEntry);
  }

  void replaceCurrent(int tabIndex, Uri uri) {
    final List<PrimaryTabRouteEntry> stack = _stackFor(tabIndex);
    stack[stack.length - 1] = stack.last.copyWith(uri: uri);
  }

  PrimaryTabRouteEntry? pop(int tabIndex) {
    final List<PrimaryTabRouteEntry> stack = _stackFor(tabIndex);
    if (stack.length <= 1) {
      return null;
    }
    stack.removeLast();
    return stack.last;
  }

  PrimaryTabRouteEntry resetToRoot(int tabIndex) {
    final List<PrimaryTabRouteEntry> stack = _stackFor(tabIndex);
    final Uri rootUri = _rootUriFor(tabIndex);
    final PrimaryTabRouteEntry rootEntry = stack.first.copyWith(
      uri: rootUri,
      routeKey: AppConfig.routeKeyForUri(rootUri),
      isLoading: false,
      clearError: true,
    );
    _stacks[tabIndex] = <PrimaryTabRouteEntry>[rootEntry];
    return rootEntry;
  }

  void updatePage(int tabIndex, EasyCopyPage page) {
    final List<PrimaryTabRouteEntry> stack = _stackFor(tabIndex);
    final Uri pageUri = _normalizeSessionUri(Uri.parse(page.uri));
    stack[stack.length - 1] = stack.last.copyWith(
      uri: pageUri,
      routeKey: AppConfig.routeKeyForUri(pageUri),
      page: page,
      isLoading: false,
      clearError: true,
    );
  }

  void updateScroll(int tabIndex, String routeKey, double offset) {
    _updateMatchingRoute(
      tabIndex,
      routeKey,
      (PrimaryTabRouteEntry entry) =>
          entry.copyWith(standardScrollOffset: offset < 0 ? 0 : offset),
    );
  }

  void updateError(int tabIndex, String routeKey, String? message) {
    _updateMatchingRoute(
      tabIndex,
      routeKey,
      (PrimaryTabRouteEntry entry) => entry.copyWith(
        isLoading: false,
        errorMessage: (message ?? '').isEmpty ? null : message,
      ),
    );
  }

  void updateCurrent(
    int tabIndex,
    PrimaryTabRouteEntry Function(PrimaryTabRouteEntry entry) updater,
  ) {
    final List<PrimaryTabRouteEntry> stack = _stackFor(tabIndex);
    stack[stack.length - 1] = updater(stack.last);
  }

  List<PrimaryTabRouteEntry> stackForTab(int tabIndex) {
    return List<PrimaryTabRouteEntry>.unmodifiable(_stackFor(tabIndex));
  }

  void _updateMatchingRoute(
    int tabIndex,
    String routeKey,
    PrimaryTabRouteEntry Function(PrimaryTabRouteEntry entry) updater,
  ) {
    final List<PrimaryTabRouteEntry> stack = _stackFor(tabIndex);
    final int index = stack.lastIndexWhere(
      (PrimaryTabRouteEntry entry) => entry.routeKey == routeKey,
    );
    if (index == -1) {
      return;
    }
    stack[index] = updater(stack[index]);
  }

  List<PrimaryTabRouteEntry> _stackFor(int tabIndex) {
    final List<PrimaryTabRouteEntry>? stack = _stacks[tabIndex];
    if (stack != null) {
      return stack;
    }
    final Uri rootUri = _rootUriFor(tabIndex);
    final List<PrimaryTabRouteEntry> nextStack = <PrimaryTabRouteEntry>[
      PrimaryTabRouteEntry.root(rootUri),
    ];
    _stacks[tabIndex] = nextStack;
    return nextStack;
  }

  Uri _rootUriFor(int tabIndex) {
    final Uri? rootUri = _rootUris[tabIndex];
    if (rootUri == null) {
      throw RangeError('No root URI configured for tab $tabIndex.');
    }
    return rootUri;
  }

  static bool _sameRoute(Uri left, Uri right) {
    return _normalizeSessionUri(left).toString() ==
        _normalizeSessionUri(right).toString();
  }
}
