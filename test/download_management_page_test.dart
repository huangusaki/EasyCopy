import 'package:easy_copy/models/app_preferences.dart';
import 'package:easy_copy/services/download_queue_store.dart';
import 'package:easy_copy/services/download_storage_service.dart';
import 'package:easy_copy/widgets/download_management_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DownloadQueueTask buildTask({
    required String id,
    required String chapterLabel,
    required DownloadQueueTaskStatus status,
    String progressLabel = '等待缓存',
  }) {
    return DownloadQueueTask(
      id: id,
      comicKey: '/comic/demo',
      chapterKey: '/comic/demo/chapter/$id',
      comicTitle: '示例漫画',
      comicUri: 'https://www.2026copy.com/comic/demo',
      coverUrl: 'https://img.example/demo.jpg',
      chapterLabel: chapterLabel,
      chapterHref: 'https://www.2026copy.com/comic/demo/chapter/$id',
      status: status,
      progressLabel: progressLabel,
      completedImages: status == DownloadQueueTaskStatus.downloading ? 2 : 0,
      totalImages: status == DownloadQueueTaskStatus.downloading ? 10 : 0,
      createdAt: DateTime(2026, 3, 8, 12),
      updatedAt: DateTime(2026, 3, 8, 12, 5),
      errorMessage: status == DownloadQueueTaskStatus.failed ? '网络异常' : '',
    );
  }

  testWidgets('DownloadManagementPage renders sections and forwards actions', (
    WidgetTester tester,
  ) async {
    int pauseTaps = 0;
    int stopComicTaps = 0;
    int removeTaskTaps = 0;
    int retryTaskTaps = 0;
    int pickDirectoryTaps = 0;

    final ValueNotifier<DownloadQueueSnapshot> queueNotifier =
        ValueNotifier<DownloadQueueSnapshot>(
          DownloadQueueSnapshot(
            tasks: <DownloadQueueTask>[
              buildTask(
                id: 'chapter-1',
                chapterLabel: '第1话',
                status: DownloadQueueTaskStatus.downloading,
                progressLabel: '第1话 · 正在下载 2/10',
              ),
              buildTask(
                id: 'chapter-2',
                chapterLabel: '第2话',
                status: DownloadQueueTaskStatus.failed,
                progressLabel: '失败：网络异常',
              ),
            ],
          ),
        );
    final ValueNotifier<DownloadStorageState> storageNotifier =
        ValueNotifier<DownloadStorageState>(
          const DownloadStorageState(
            preferences: DownloadPreferences(),
            basePath: 'D:\\Comics',
            rootPath: 'D:\\Comics\\EasyCopyDownloads',
            isCustom: false,
            isWritable: true,
            mayBeRemovedOnUninstall: true,
          ),
        );
    final ValueNotifier<bool> busyNotifier = ValueNotifier<bool>(false);

    await tester.pumpWidget(
      MaterialApp(
        home: DownloadManagementPage(
          queueListenable: queueNotifier,
          storageStateListenable: storageNotifier,
          storageBusyListenable: busyNotifier,
          supportsCustomDirectorySelection: true,
          onPauseQueue: () {
            pauseTaps += 1;
            queueNotifier.value = queueNotifier.value.copyWith(isPaused: true);
          },
          onResumeQueue: () {},
          onStopComicTasks: (_) {
            stopComicTaps += 1;
          },
          onRemoveTask: (_) {
            removeTaskTaps += 1;
          },
          onRetryTask: (_) {
            retryTaskTaps += 1;
          },
          onPickStorageDirectory: () {
            pickDirectoryTaps += 1;
          },
          onResetStorageDirectory: () {},
        ),
      ),
    );

    expect(find.text('当前任务'), findsOneWidget);
    expect(find.text('缓存队列'), findsOneWidget);

    await tester.tap(find.text('暂停'));
    await tester.pump();
    expect(pauseTaps, 1);

    await tester.tap(find.text('停止'));
    await tester.pump();
    expect(stopComicTaps, 1);

    final TextButton retryButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '重试'),
    );
    retryButton.onPressed!();
    await tester.pump();
    expect(retryTaskTaps, 1);

    final TextButton removeButton = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '移出'),
    );
    removeButton.onPressed!();
    await tester.pump();
    expect(removeTaskTaps, 1);

    await tester.drag(find.byType(ListView).first, const Offset(0, -500));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('选择存储位置'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('卸载应用后'), findsOneWidget);
    await tester.tap(find.text('选择存储位置'));
    await tester.pump();
    expect(pickDirectoryTaps, 1);
  });
}
