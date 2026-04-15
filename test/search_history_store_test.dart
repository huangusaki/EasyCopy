import 'dart:io';

import 'package:easy_copy/services/search_history_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('records search history, deduplicates, and persists', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'easycopy_search_history_',
    );
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final SearchHistoryStore store = SearchHistoryStore(
      directoryProvider: () async => tempDir,
    );
    await store.ensureInitialized();
    expect(store.items, isEmpty);

    await store.record('  A  ');
    await store.record('B');
    await store.record('A');
    expect(store.items, <String>['A', 'B']);

    for (int index = 0; index < 12; index += 1) {
      await store.record('q$index');
    }
    expect(store.items.length, 10);
    expect(store.items.first, 'q11');

    final SearchHistoryStore reloaded = SearchHistoryStore(
      directoryProvider: () async => tempDir,
    );
    await reloaded.ensureInitialized();
    expect(reloaded.items, store.items);
  });
}

