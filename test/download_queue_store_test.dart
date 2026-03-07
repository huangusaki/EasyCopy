import 'dart:io';

import 'package:easy_copy/services/download_queue_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'download queue store normalizes unfinished work back to queued',
    () async {
      final Directory tempDir = await Directory.systemTemp.createTemp(
        'easy_copy_queue_store',
      );
      addTearDown(() => tempDir.delete(recursive: true));

      final DownloadQueueStore store = DownloadQueueStore(
        directoryProvider: () async => tempDir,
      );

      await store.write(
        DownloadQueueSnapshot(
          isPaused: true,
          tasks: <DownloadQueueTask>[
            DownloadQueueTask(
              id: 'task-1',
              comicKey: '/comic/demo',
              chapterKey: '/comic/demo/chapter/1',
              comicTitle: 'Demo Comic',
              comicUri: 'https://www.2026copy.com/comic/demo',
              coverUrl: 'https://img.example/demo.jpg',
              chapterLabel: 'Chapter 1',
              chapterHref: 'https://www.2026copy.com/comic/demo/chapter/1',
              status: DownloadQueueTaskStatus.downloading,
              progressLabel: '正在缓存 Chapter 1',
              completedImages: 3,
              totalImages: 10,
              createdAt: DateTime(2026, 3, 7, 10),
              updatedAt: DateTime(2026, 3, 7, 10, 5),
            ),
          ],
        ),
      );

      final DownloadQueueSnapshot restoredSnapshot = await store.read();

      expect(restoredSnapshot.isPaused, isTrue);
      expect(restoredSnapshot.tasks, hasLength(1));
      expect(
        restoredSnapshot.tasks.single.status,
        DownloadQueueTaskStatus.queued,
      );
      expect(restoredSnapshot.tasks.single.completedImages, 3);
    },
  );
}
