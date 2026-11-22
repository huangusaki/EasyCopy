import 'package:flutter/material.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/services/chinese_converter.dart';
import 'package:reader/services/comic_download_service.dart';
import 'package:reader/services/reader_progress_store.dart';
import 'package:reader/services/uri_keys.dart';
import 'package:reader/theme/app_theme.dart';

class ChapterPathResolver {
  ChapterPathResolver(this._readerProgressStore);

  final ReaderProgressStore _readerProgressStore;

  String pathKey(String href) => UriKeys.pathKey(href);

  String lastReadKey(DetailPageData page) {
    return pathKey(
      _readerProgressStore.latestChapterPathKeyForCatalog(page.uri) ?? '',
    );
  }

  String? _visitedCatalog;
  int? _visitedRevision;
  Set<String> _visited = const {};
  Set<String> visitedKeys(DetailPageData page) {
    final revision = _readerProgressStore.chapterRevision.value;
    if (_visitedCatalog != page.uri || _visitedRevision != revision) {
      _visitedCatalog = page.uri;
      _visitedRevision = revision;
      _visited = _readerProgressStore
          .visitedChapterPathKeysForCatalog(page.uri)
          .map(pathKey)
          .toSet();
    }
    return _visited;
  }

  String? _downloadCatalog;
  List<CachedComicLibraryEntry>? _library;
  Set<String> _downloaded = const {};
  Set<String> downloadedKeys(
    DetailPageData page,
    List<CachedComicLibraryEntry> comics,
  ) {
    if (_downloadCatalog != page.uri || !identical(comics, _library)) {
      _downloadCatalog = page.uri;
      _library = comics;
      _downloaded = downloadedChapterKeysForDetail(
        page,
        cachedComics: comics,
        chapterPathKey: pathKey,
      );
    }
    return _downloaded;
  }
}

Set<String> downloadedChapterKeysForDetail(
  DetailPageData page, {
  required List<CachedComicLibraryEntry> cachedComics,
  required String Function(String href) chapterPathKey,
}) {
  final Uri currentDetailUri = Uri.parse(page.uri);
  final String targetPath = currentDetailUri.path;
  final CachedComicLibraryEntry? match = cachedComics
      .cast<CachedComicLibraryEntry?>()
      .firstWhere(
        (CachedComicLibraryEntry? item) =>
            item != null && Uri.tryParse(item.comicHref)?.path == targetPath,
        orElse: () => null,
      );
  if (match == null) {
    return const <String>{};
  }
  return match.chapters
      .map((CachedChapterEntry chapter) => chapterPathKey(chapter.chapterHref))
      .where((String key) => key.isNotEmpty)
      .toSet();
}

Future<List<ChapterData>?> showDetailChapterDownloadPicker({
  required BuildContext context,
  required DetailPageData page,
  required Set<String> downloadedKeys,
  required String Function(String href) chapterPathKey,
}) {
  final chapters = page.allChapters;
  return showModalBottomSheet<List<ChapterData>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) {
      final Set<String> selectedKeys = <String>{};
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          List<ChapterData> selectedChapterValues() {
            return chapters
                .where(
                  (ChapterData chapter) =>
                      selectedKeys.contains(chapterPathKey(chapter.href)),
                )
                .toList(growable: false);
          }

          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.78,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Expanded(
                          child: Text(
                            '选择要缓存的章节',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setModalState(() {
                              selectedKeys
                                ..clear()
                                ..addAll(
                                  chapters.map(
                                    (ChapterData chapter) =>
                                        chapterPathKey(chapter.href),
                                  ),
                                );
                            });
                          },
                          child: const Text('全选'),
                        ),
                        TextButton(
                          onPressed: () {
                            setModalState(selectedKeys.clear);
                          },
                          child: const Text('清空'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListenableBuilder(
                        listenable: ChineseConverter.instance,
                        builder: (BuildContext context, Widget? _) {
                          return ListView.builder(
                            itemCount: chapters.isEmpty
                                ? 0
                                : chapters.length + 1,
                            itemBuilder: (context, i) {
                              if (i == 0) {
                                return Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    4,
                                    10,
                                    4,
                                    4,
                                  ),
                                  child: Text(
                                    '全部章节',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                );
                              }
                              final chapter = chapters[i - 1];
                              final String key = chapterPathKey(chapter.href);
                              final bool isDownloaded = downloadedKeys.contains(
                                key,
                              );
                              final bool selected = selectedKeys.contains(key);
                              final Color downloadedColor = Theme.of(
                                context,
                              ).extension<AppSemanticColors>()!.success;
                              return CheckboxListTile(
                                value: selected,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                onChanged: (bool? nextValue) {
                                  setModalState(() {
                                    if (nextValue ?? false) {
                                      selectedKeys.add(key);
                                    } else {
                                      selectedKeys.remove(key);
                                    }
                                  });
                                },
                                secondary: isDownloaded
                                    ? Icon(
                                        Icons.check_circle_rounded,
                                        color: downloadedColor,
                                      )
                                    : null,
                                title: Text(
                                  ChineseConverter.instance.convert(
                                    chapter.label,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: selectedKeys.isEmpty
                            ? null
                            : () {
                                Navigator.of(
                                  context,
                                ).pop(selectedChapterValues());
                              },
                        child: Text(
                          selectedKeys.isEmpty
                              ? '请选择章节'
                              : '缓存 ${selectedKeys.length} 话',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
