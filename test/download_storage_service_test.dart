import 'dart:io';

import 'package:easy_copy/models/app_preferences.dart';
import 'package:easy_copy/services/download_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  test('download storage service resolves the default cache root', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'easy_copy_storage_default_',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final DownloadStorageService service = DownloadStorageService(
      preferencesProvider: () async => const DownloadPreferences(),
      defaultBaseDirectoryProvider: () async => tempDir,
    );

    final DownloadStorageState state = await service.resolveState();

    expect(state.isReady, isTrue);
    expect(
      state.rootPath,
      '${tempDir.path}${Platform.pathSeparator}'
      '${DownloadStorageService.downloadsDirectoryName}',
    );
    expect(Directory(state.rootPath).existsSync(), isTrue);
  });

  test(
    'download storage service uses a custom base path when configured',
    () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'easy_copy_storage_custom_',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final DownloadStorageService service = DownloadStorageService(
        preferencesProvider: () async => DownloadPreferences(
          mode: DownloadStorageMode.customDirectory,
          customBasePath: tempDir.path,
        ),
      );

      final DownloadStorageState state = await service.resolveState();

      expect(state.isReady, isTrue);
      expect(state.isCustom, isTrue);
      expect(state.basePath, tempDir.path);
    },
  );

  test('download storage service reports an invalid custom path', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'easy_copy_storage_invalid_',
    );
    addTearDown(() => tempDir.delete(recursive: true));
    final File invalidBase = File(
      '${tempDir.path}${Platform.pathSeparator}not-a-directory.txt',
    );
    await invalidBase.writeAsString('demo');

    final DownloadStorageService service = DownloadStorageService(
      preferencesProvider: () async => DownloadPreferences(
        mode: DownloadStorageMode.customDirectory,
        customBasePath: invalidBase.path,
      ),
    );

    final DownloadStorageState state = await service.resolveState();

    expect(state.isReady, isFalse);
    expect(state.errorMessage, isNotEmpty);
  });

  test(
    'loadCustomDirectoryCandidates excludes the default path and duplicate entries',
    () async {
      final Directory rootDir = await Directory.systemTemp.createTemp(
        'easy_copy_storage_candidates_',
      );
      addTearDown(() => rootDir.delete(recursive: true));
      final Directory defaultBase = Directory(
        '${rootDir.path}${Platform.pathSeparator}default',
      );
      final Directory removableBase = Directory(
        '${rootDir.path}${Platform.pathSeparator}sdcard',
      );
      final Directory secondaryBase = Directory(
        '${rootDir.path}${Platform.pathSeparator}secondary',
      );
      await defaultBase.create(recursive: true);
      await removableBase.create(recursive: true);
      await secondaryBase.create(recursive: true);
      final File invalidBase = File(
        '${rootDir.path}${Platform.pathSeparator}not-a-directory.txt',
      );
      await invalidBase.writeAsString('demo');

      final DownloadStorageService service = DownloadStorageService(
        preferencesProvider: () async => const DownloadPreferences(),
        defaultBaseDirectoryProvider: () async => defaultBase,
        customBaseDirectoriesProvider: () async => <Directory>[
          defaultBase,
          removableBase,
          removableBase,
          Directory(invalidBase.path),
          secondaryBase,
        ],
      );

      final List<DownloadStorageState> candidates = await service
          .loadCustomDirectoryCandidates();

      expect(service.supportsCustomDirectorySelection, isTrue);
      expect(
        candidates.map((DownloadStorageState state) => state.basePath),
        equals(<String>[removableBase.path, secondaryBase.path]..sort()),
      );
      expect(
        candidates.every((DownloadStorageState state) => state.isReady),
        isTrue,
      );
    },
  );

  test(
    'loadCustomDirectoryCandidates keeps Android subdirectories when only one external root exists',
    () async {
      final Directory rootDir = await Directory.systemTemp.createTemp(
        'easy_copy_storage_android_candidates_',
      );
      addTearDown(() => rootDir.delete(recursive: true));
      final Directory defaultBase = Directory(
        '${rootDir.path}${Platform.pathSeparator}primary',
      );
      final Directory downloadsBase = Directory(
        '${defaultBase.path}${Platform.pathSeparator}Download',
      );
      final Directory documentsBase = Directory(
        '${defaultBase.path}${Platform.pathSeparator}Documents',
      );
      final Directory cacheBase = Directory(
        '${rootDir.path}${Platform.pathSeparator}cache',
      );
      await defaultBase.create(recursive: true);

      final DownloadStorageService service = DownloadStorageService(
        preferencesProvider: () async => const DownloadPreferences(),
        defaultBaseDirectoryProvider: () async => defaultBase,
        androidExternalStorageDirectoriesProvider:
            (StorageDirectory? type) async {
              switch (type) {
                case null:
                  return <Directory>[defaultBase];
                case StorageDirectory.downloads:
                  return <Directory>[downloadsBase];
                case StorageDirectory.documents:
                  return <Directory>[documentsBase];
                default:
                  return const <Directory>[];
              }
            },
        androidExternalCacheDirectoriesProvider: () async => <Directory>[
          cacheBase,
        ],
      );

      final List<DownloadStorageState> candidates = await service
          .loadCustomDirectoryCandidates();

      expect(service.supportsCustomDirectorySelection, isTrue);
      expect(
        candidates.map((DownloadStorageState state) => state.basePath).toSet(),
        equals(<String>{
          downloadsBase.path,
          documentsBase.path,
          cacheBase.path,
        }),
      );
      expect(
        candidates.every((DownloadStorageState state) => state.isReady),
        isTrue,
      );
    },
  );
}
