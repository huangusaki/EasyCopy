import 'dart:convert';
import 'dart:io';

import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/services/comic_download_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  ReaderPageData buildReaderPage() {
    return ReaderPageData(
      title: 'Chapter 1',
      uri: 'https://www.2026copy.com/comic/demo/chapter/1',
      comicTitle: 'Demo Comic',
      chapterTitle: 'Chapter 1',
      progressLabel: '1/2',
      imageUrls: const <String>[
        'https://cdn.example/chapter-1/001.jpg',
        'https://cdn.example/chapter-1/002.png',
      ],
      prevHref: '',
      nextHref: '',
      catalogHref: 'https://www.2026copy.com/comic/demo',
      contentKey: 'chapter-1',
    );
  }

  test('downloadChapter resumes from existing image files', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'easy_copy_download_service',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final List<String> requestedUrls = <String>[];
    final ComicDownloadService service = ComicDownloadService(
      client: MockClient((http.Request request) async {
        requestedUrls.add(request.url.toString());
        return http.Response.bytes(
          utf8.encode('image:${request.url.pathSegments.last}'),
          200,
          headers: <String, String>{'content-type': 'image/png'},
        );
      }),
      baseDirectoryProvider: () async => tempDir,
    );

    final Directory chapterDirectory = Directory(
      '${tempDir.path}${Platform.pathSeparator}EasyCopyDownloads'
      '${Platform.pathSeparator}Demo Comic'
      '${Platform.pathSeparator}Chapter 1',
    );
    await chapterDirectory.create(recursive: true);
    await File(
      '${chapterDirectory.path}${Platform.pathSeparator}001.jpg',
    ).writeAsBytes(utf8.encode('cached-001'));

    final ChapterDownloadResult result = await service.downloadChapter(
      buildReaderPage(),
      chapterLabel: 'Chapter 1',
      comicUri: 'https://www.2026copy.com/comic/demo',
      coverUrl: 'https://img.example/demo.jpg',
    );

    expect(
      requestedUrls,
      equals(<String>['https://cdn.example/chapter-1/002.png']),
    );
    expect(result.fileCount, 2);
    expect(
      File(
        '${chapterDirectory.path}${Platform.pathSeparator}001.jpg',
      ).existsSync(),
      isTrue,
    );
    expect(
      File(
        '${chapterDirectory.path}${Platform.pathSeparator}002.png',
      ).existsSync(),
      isTrue,
    );

    final Map<String, Object?> manifest =
        jsonDecode(await result.manifestFile.readAsString())
            as Map<String, Object?>;
    expect(manifest['imageCount'], 2);
  });

  test('deleteCachedComic removes the comic directory from disk', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'easy_copy_download_delete',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final ComicDownloadService service = ComicDownloadService(
      client: MockClient((http.Request request) async {
        return http.Response.bytes(
          utf8.encode('image:${request.url.pathSegments.last}'),
          200,
          headers: <String, String>{'content-type': 'image/jpeg'},
        );
      }),
      baseDirectoryProvider: () async => tempDir,
    );

    await service.downloadChapter(
      buildReaderPage(),
      chapterLabel: 'Chapter 1',
      comicUri: 'https://www.2026copy.com/comic/demo',
      coverUrl: 'https://img.example/demo.jpg',
    );

    final List<CachedComicLibraryEntry> library = await service
        .loadCachedLibrary();
    expect(library, hasLength(1));

    final Directory comicDirectory = Directory(
      '${tempDir.path}${Platform.pathSeparator}EasyCopyDownloads'
      '${Platform.pathSeparator}Demo Comic',
    );
    expect(comicDirectory.existsSync(), isTrue);

    await service.deleteCachedComic(library.single);

    expect(comicDirectory.existsSync(), isFalse);
  });
}
