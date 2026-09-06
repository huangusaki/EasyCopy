import 'dart:io';

/// Storage ownership, independent of task ids and execution generations.
class DownloadCleanupScope {
  DownloadCleanupScope({
    Iterable<String> comicKeys = const <String>[],
    Iterable<String> comicPaths = const <String>[],
    Iterable<String> chapterPaths = const <String>[],
  }) : comicKeys = comicKeys.toSet(),
       comicPaths = comicPaths.map(_normalizePath).toSet(),
       chapterPaths = chapterPaths.map(_normalizePath).toSet();

  final Set<String> comicKeys;
  final Set<String> comicPaths;
  final Set<String> chapterPaths;

  bool contains({
    required String comicKey,
    required String comicPath,
    required String chapterPath,
  }) =>
      comicKeys.contains(comicKey) ||
      comicPaths.contains(_normalizePath(comicPath)) ||
      chapterPaths.contains(_normalizePath(chapterPath));

  static String _normalizePath(String value) {
    final String path = value.replaceAll('\\', '/');
    return Platform.isWindows ? path.toLowerCase() : path;
  }
}

/// A cleanup reserves its storage before queue removal becomes visible. Only
/// downloads owning that storage wait; other chapters can still be scheduled.
class DownloadCleanupGuard {
  final Set<DownloadCleanupScope> _reservations = <DownloadCleanupScope>{};

  void reserve(DownloadCleanupScope scope) => _reservations.add(scope);
  void release(DownloadCleanupScope scope) => _reservations.remove(scope);

  bool blocks({
    required String comicKey,
    required String comicPath,
    required String chapterPath,
  }) => _reservations.any(
    (DownloadCleanupScope scope) => scope.contains(
      comicKey: comicKey,
      comicPath: comicPath,
      chapterPath: chapterPath,
    ),
  );
}
