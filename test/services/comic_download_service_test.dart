import 'dart:convert';
import 'dart:io';

import 'package:easy_copy/models/app_preferences.dart';
import 'package:easy_copy/services/comic_download_service.dart';
import 'package:easy_copy/services/download_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ComicDownloadService', () {
    late Directory tempDirectory;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp(
        'copy_fullter_download_service_test_',
      );
    });

    tearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test(
      'loadCachedLibrary reads manifests from comic/chapter directories',
      () async {
        final ComicDownloadService service = ComicDownloadService(
          baseDirectoryProvider: () async => tempDirectory,
        );
        final Directory root = Directory(
          '${tempDirectory.path}${Platform.pathSeparator}'
          '${DownloadStorageService.downloadsDirectoryName}',
        );
        final Directory chapterDirectory = Directory(
          '${root.path}${Platform.pathSeparator}Comic A'
          '${Platform.pathSeparator}Chapter 1',
        );
        await chapterDirectory.create(recursive: true);
        await File(
          '${chapterDirectory.path}${Platform.pathSeparator}001.jpg',
        ).writeAsString('image');
        await File(
          '${chapterDirectory.path}${Platform.pathSeparator}manifest.json',
        ).writeAsString(
          jsonEncode(<String, Object?>{
            'comicTitle': 'Comic A',
            'comicUri': 'https://example.com/comic/a',
            'coverUrl': 'https://example.com/cover-a.jpg',
            'chapterLabel': 'Chapter 1',
            'chapterHref': 'https://example.com/comic/a/chapter/1',
            'sourceUri': 'https://example.com/comic/a/chapter/1',
            'downloadedAt': DateTime(2026, 4, 1).toIso8601String(),
            'files': <String>['001.jpg'],
            'imageCount': 1,
          }),
        );

        final List<CachedComicLibraryEntry> library = await service
            .loadCachedLibrary();

        expect(library, hasLength(1));
        expect(library.first.comicTitle, 'Comic A');
        expect(library.first.cachedChapterCount, 1);
        expect(library.first.chapters.first.chapterTitle, 'Chapter 1');
      },
    );

    test('migrateCacheRoot rejects nested target directories', () async {
      final ComicDownloadService service = ComicDownloadService(
        baseDirectoryProvider: () async => tempDirectory,
      );
      final Directory sourceRoot = Directory(
        '${tempDirectory.path}${Platform.pathSeparator}'
        '${DownloadStorageService.downloadsDirectoryName}',
      );
      await sourceRoot.create(recursive: true);

      final DownloadPreferences from = const DownloadPreferences();
      final DownloadPreferences to = DownloadPreferences(
        mode: DownloadStorageMode.customDirectory,
        customBasePath:
            '${sourceRoot.path}${Platform.pathSeparator}nested_target',
        usePickedDirectoryAsRoot: true,
      );

      await expectLater(
        service.migrateCacheRoot(from: from, to: to),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('migrateCacheRoot cleans source directory asynchronously', () async {
      final ComicDownloadService service = ComicDownloadService(
        baseDirectoryProvider: () async => tempDirectory,
      );
      final Directory sourceRoot = Directory(
        '${tempDirectory.path}${Platform.pathSeparator}'
        '${DownloadStorageService.downloadsDirectoryName}',
      );
      final Directory sourceChapterDirectory = Directory(
        '${sourceRoot.path}${Platform.pathSeparator}Comic A'
        '${Platform.pathSeparator}Chapter 1',
      );
      await sourceChapterDirectory.create(recursive: true);
      await File(
        '${sourceChapterDirectory.path}${Platform.pathSeparator}001.jpg',
      ).writeAsString('image');

      final Directory targetRoot = Directory(
        '${tempDirectory.path}${Platform.pathSeparator}migrated_cache',
      );
      final DownloadStorageMigrationResult result = await service
          .migrateCacheRoot(
            from: const DownloadPreferences(),
            to: DownloadPreferences(
              mode: DownloadStorageMode.customDirectory,
              customBasePath: targetRoot.path,
              usePickedDirectoryAsRoot: true,
            ),
          );

      expect(result.cleanupFuture, isNotNull);
      await result.cleanupFuture;

      expect(
        await File(
          '${targetRoot.path}${Platform.pathSeparator}Comic A'
          '${Platform.pathSeparator}Chapter 1'
          '${Platform.pathSeparator}001.jpg',
        ).exists(),
        isTrue,
      );
      expect(
        await Directory(
          '${sourceRoot.path}${Platform.pathSeparator}Comic A',
        ).exists(),
        isFalse,
      );
    });
  });
}
