import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/widgets/comic_quick_preview_sheet.dart';

void main() {
  Future<void> openPreview(
    WidgetTester tester, {
    required ComicCardData item,
    VoidCallback? onBlockComic,
    ValueChanged<LinkAction>? onBlockAuthor,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () => showComicQuickPreview(
                context,
                item: item,
                onOpenDetail: () {},
                onBlockComic: onBlockComic,
                onBlockAuthor: onBlockAuthor,
              ),
              child: const Text('打开预览'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开预览'));
    await tester.pumpAndSettle();
  }

  testWidgets('横屏多作者预览可滚动并屏蔽最后一位作者', (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    LinkAction? blockedAuthor;
    await openPreview(
      tester,
      item: const ComicCardData(
        title: '漫画',
        coverUrl: '',
        href: '/comic/example',
        authorLinks: <LinkAction>[
          LinkAction(label: '作者一', href: '/author/one'),
          LinkAction(label: '作者二', href: '/author/two'),
          LinkAction(label: '作者三', href: '/author/three'),
        ],
      ),
      onBlockComic: () {},
      onBlockAuthor: (LinkAction author) => blockedAuthor = author,
    );
    expect(tester.takeException(), isNull);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('作者三'));
    await tester.pumpAndSettle();
    expect(blockedAuthor?.href, '/author/three');
    expect(find.text('屏蔽作者'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('只有作者名称时仍能屏蔽作者', (tester) async {
    LinkAction? blockedAuthor;
    await openPreview(
      tester,
      item: const ComicCardData(
        title: '漫画',
        subtitle: '作者：名称作者',
        coverUrl: '',
        href: '/comic/example',
      ),
      onBlockAuthor: (LinkAction author) => blockedAuthor = author,
    );
    await tester.tap(find.text('名称作者'));
    await tester.pumpAndSettle();
    expect(blockedAuthor?.label, '名称作者');
    expect(blockedAuthor?.href, isEmpty);
    expect(find.text('屏蔽作者'), findsNothing);
  });

  testWidgets('无作者时仅提供漫画屏蔽且点击后关闭预览', (tester) async {
    int comicBlocks = 0;
    await openPreview(
      tester,
      item: const ComicCardData(
        title: '漫画',
        coverUrl: '',
        href: '/comic/example',
      ),
      onBlockComic: () => comicBlocks++,
      onBlockAuthor: (_) => fail('无作者不应提供作者屏蔽'),
    );
    expect(find.text('屏蔽作者'), findsNothing);
    await tester.tap(find.text('屏蔽漫画'));
    await tester.pumpAndSettle();
    expect(comicBlocks, 1);
    expect(find.text('屏蔽漫画'), findsNothing);
  });
}
