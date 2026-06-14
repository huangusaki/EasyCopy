import 'package:flutter/material.dart';
import 'package:reader/app_screen/models.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/services/comic_download_service.dart';
import 'package:reader/services/reader_progress_store.dart';
import 'package:reader/services/uri_keys.dart';
import 'package:reader/theme/app_theme.dart';

class ChapterPathResolver {
  const ChapterPathResolver(this._readerProgressStore);

  final ReaderProgressStore _readerProgressStore;

  String pathKey(String href) => UriKeys.pathKey(href);

  String lastReadKey(DetailPageData page) {
    return _readerProgressStore.latestChapterPathKeyForCatalog(page.uri) ?? '';
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

List<ChapterPickerSection> chapterPickerSections(
  DetailPageData page, {
  required String Function(String href) chapterPathKey,
}) {
  final List<ChapterData> allChapters = page.chapters.isNotEmpty
      ? page.chapters
      : page.chapterGroups
            .expand((ChapterGroupData group) => group.chapters)
            .fold<Map<String, ChapterData>>(<String, ChapterData>{}, (
              Map<String, ChapterData> chaptersByKey,
              ChapterData chapter,
            ) {
              final String key = chapterPathKey(chapter.href);
              if (key.isNotEmpty && !chaptersByKey.containsKey(key)) {
                chaptersByKey[key] = chapter;
              }
              return chaptersByKey;
            })
            .values
            .toList(growable: false);
  if (allChapters.isEmpty) {
    return const <ChapterPickerSection>[];
  }
  return <ChapterPickerSection>[
    ChapterPickerSection(label: '全部章节', chapters: allChapters),
  ];
}

Future<List<ChapterData>?> showDetailChapterDownloadPicker({
  required BuildContext context,
  required DetailPageData page,
  required Set<String> downloadedKeys,
  required String Function(String href) chapterPathKey,
}) {
  final List<ChapterPickerSection> sections = chapterPickerSections(
    page,
    chapterPathKey: chapterPathKey,
  );
  return showModalBottomSheet<List<ChapterData>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (BuildContext context) {
      final Set<String> selectedKeys = <String>{};
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          List<ChapterData> selectedChapterValues() {
            return sections
                .expand((ChapterPickerSection section) => section.chapters)
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
                                  sections
                                      .expand(
                                        (ChapterPickerSection section) =>
                                            section.chapters,
                                      )
                                      .map(
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
                      child: ListView(
                        shrinkWrap: true,
                        children: sections
                            .expand((ChapterPickerSection section) {
                              return <Widget>[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    4,
                                    10,
                                    4,
                                    4,
                                  ),
                                  child: Text(
                                    section.label,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                ...section.chapters.map((ChapterData chapter) {
                                  final String key = chapterPathKey(
                                    chapter.href,
                                  );
                                  final bool isDownloaded = downloadedKeys
                                      .contains(key);
                                  final bool selected = selectedKeys.contains(
                                    key,
                                  );
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
                                    title: Text(chapter.label),
                                  );
                                }),
                              ];
                            })
                            .toList(growable: false),
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
