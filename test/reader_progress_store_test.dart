import 'dart:convert';
import 'dart:io';

import 'package:easy_copy/services/reader_progress_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ReaderProgressStore migrates legacy offset entries', () async {
    final Directory tempDirectory = await Directory.systemTemp.createTemp(
      'easy_copy_reader_progress_legacy_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final File file = File(
      '${tempDirectory.path}${Platform.pathSeparator}reader_progress.json',
    );
    await file.writeAsString(
      jsonEncode(<Map<String, Object?>>[
        <String, Object?>{
          'key': 'chapter-1',
          'offset': 128.5,
          'updatedAt': '2026-03-07T10:20:30.000',
        },
      ]),
    );

    final ReaderProgressStore store = ReaderProgressStore(
      directoryProvider: () async => tempDirectory,
    );

    final ReaderPosition? position = await store.readPosition('chapter-1');

    expect(position, isNotNull);
    expect(position?.isScroll, isTrue);
    expect(position?.offset, 128.5);
  });

  test('ReaderProgressStore persists paged positions', () async {
    final Directory tempDirectory = await Directory.systemTemp.createTemp(
      'easy_copy_reader_progress_paged_',
    );
    addTearDown(() => tempDirectory.delete(recursive: true));

    final ReaderProgressStore store = ReaderProgressStore(
      directoryProvider: () async => tempDirectory,
    );

    await store.writePosition(
      'chapter-2',
      ReaderPosition.paged(pageIndex: 7, pageOffset: 64),
    );
    final ReaderPosition? position = await store.readPosition('chapter-2');

    expect(position, isNotNull);
    expect(position?.isPaged, isTrue);
    expect(position?.pageIndex, 7);
    expect(position?.pageOffset, 64);
  });
}
