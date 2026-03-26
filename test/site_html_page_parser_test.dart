import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/services/site_html_page_parser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart';

String fixturePath(String name) {
  return 'test${Platform.pathSeparator}fixtures${Platform.pathSeparator}'
      'site${Platform.pathSeparator}$name';
}

void main() {
  const SiteHtmlPageParser parser = SiteHtmlPageParser.instance;

  test('parses homepage fixture into home sections and feature card', () async {
    final String html = await File(fixturePath('homepage.html')).readAsString();
    final HomePageData page =
        await parser.parsePage(Uri.parse('https://www.2026copy.com/'), html)
            as HomePageData;

    expect(page.title, '首頁');
    expect(page.heroBanners, isNotEmpty);
    expect(page.sections.length, greaterThanOrEqualTo(3));
    expect(page.sections.first.title, contains('漫畫推薦'));
    expect(page.sections.first.items, isNotEmpty);
    expect(page.sections.first.href, 'https://www.2026copy.com/recommend');
    expect(page.feature, isNotNull);
    expect(page.feature!.title, contains('秋番漫畫2025'));
    expect(page.feature!.href, contains('/topic/'));
  });

  test(
    'parses discover fixture with filters, items, spotlight, and pager',
    () async {
      final String html = await File(fixturePath('comics.html')).readAsString();
      final DiscoverPageData page =
          await parser.parsePage(
                Uri.parse(
                  'https://www.2026copy.com/comics?ordering=-datetime_updated',
                ),
                html,
              )
              as DiscoverPageData;

      expect(page.filters.length, 4);
      expect(page.filters.first.label, '題材');
      expect(
        page.filters.last.options.any((LinkAction item) => item.active),
        isTrue,
      );
      expect(page.items, hasLength(50));
      expect(
        page.items.map((ComicCardData item) => item.href),
        contains('https://www.2026copy.com/comic/omolaoshiheji'),
      );
      expect(page.spotlight, hasLength(5));
      expect(page.spotlight.first.title, '一日凌辱體驗');
      expect(page.pager.currentLabel, '1');
      expect(page.pager.nextHref, contains('offset=50'));
    },
  );

  test('parses discover inline list with mixed quotes in titles', () async {
    const String html = '''
<!DOCTYPE html>
<html lang="zh-hant">
  <head>
    <title>發現 - 拷貝漫畫 拷贝漫画</title>
  </head>
  <body>
    <main class="content-box">
      <div class="container exemptComicList">
        <div class="row exemptComic-box" list="[{&#x27;path_word&#x27;: &#x27;queensorders&#x27;, &#x27;name&#x27;: &quot;碧藍航線 Queen&#x27;s Orders&quot;, &#x27;cover&#x27;: &#x27;https://sq.mangafunb.fun/q/queensorders/cover/1651100048.jpg.328x422.jpg&#x27;, &#x27;status&#x27;: 0, &#x27;author&#x27;: [{&#x27;name&#x27;: &#x27;槌居&#x27;, &#x27;path_word&#x27;: &#x27;槌居&#x27;}]}]"></div>
      </div>
    </main>
  </body>
</html>
''';

    final DiscoverPageData page =
        await parser.parsePage(
              Uri.parse('https://www.2026copy.com/comics'),
              html,
            )
            as DiscoverPageData;

    expect(page.items, hasLength(1));
    expect(page.items.first.title, "碧藍航線 Queen's Orders");
    expect(
      page.items.first.href,
      'https://www.2026copy.com/comic/queensorders',
    );
    expect(page.items.first.subtitle, '作者：槌居');
  });

  test('parses rank fixture with active tabs and ranking cards', () async {
    final String html = await File(fixturePath('rank.html')).readAsString();
    final RankPageData page =
        await parser.parsePage(
              Uri.parse('https://www.2026copy.com/rank?type=male&table=day'),
              html,
            )
            as RankPageData;

    expect(page.title, contains('排行'));
    expect(page.categories.any((LinkAction item) => item.active), isTrue);
    expect(
      page.categories.firstWhere((LinkAction item) => item.active).label,
      contains('男頻'),
    );
    expect(
      page.periods.firstWhere((LinkAction item) => item.active).label,
      '日榜(上升最快)',
    );
    expect(page.items, hasLength(50));
    expect(page.items.first.title, '魔都精兵的奴隸');
    expect(
      page.items.first.href,
      'https://www.2026copy.com/comic/modujingbingdenuli',
    );
  });

  test('parses reader pages from encrypted contentKey payloads', () async {
    const String cct = 'op0zzpvv.nmn.o0p';
    final String contentKey = _encryptReaderPayload(cct, <Object?>[
      <String, Object?>{'url': 'https://cdn.example.com/reader/001.jpg'},
      <String, Object?>{'url': 'https://cdn.example.com/reader/002.jpg'},
      <String, Object?>{'url': 'https://cdn.example.com/reader/003.jpg'},
    ]);
    final String html =
        '''
<!DOCTYPE html>
<html lang="zh-hant">
  <head>
    <title>夢醒後的灰 - 第05話 - 拷貝漫畫 拷贝漫画</title>
  </head>
  <body>
    <h4 class="header">夢醒後的灰/第05話</h4>
    <div class="container-fluid comicContent">
      <div class="container comic-size-1">
        <ul class="comicContent-list comic-size-1"></ul>
      </div>
    </div>
    <div class="footer">
      <div class="comicContent-prev index"><a href="/">首頁</a></div>
      <div class="comicContent-prev">
        <a href="/comic/mongxinhoudehui/chapter/prev-id">上一話</a>
      </div>
      <div class="comicContent-footer-txt"><span>第6 / 6話</span></div>
      <div class="comicContent-next">
        <a href="/comic/mongxinhoudehui/chapter/next-id">下一話</a>
      </div>
      <div class="comicContent-prev list"><a href="/comic/mongxinhoudehui">目錄</a></div>
    </div>
    <script>
      var cct = '$cct';
      var contentKey = '$contentKey';
    </script>
  </body>
</html>
''';

    final ReaderPageData page =
        await parser.parsePage(
              Uri.parse(
                'https://www.2026copy.com/comic/mongxinhoudehui/chapter/demo-id',
              ),
              html,
            )
            as ReaderPageData;

    expect(page.title, '夢醒後的灰/第05話');
    expect(page.comicTitle, '夢醒後的灰');
    expect(page.chapterTitle, '第05話');
    expect(page.progressLabel, '第6 / 6話');
    expect(page.imageUrls, hasLength(3));
    expect(page.imageUrls.first, 'https://cdn.example.com/reader/001.jpg');
    expect(page.prevHref, contains('/comic/mongxinhoudehui/chapter/prev-id'));
    expect(page.nextHref, contains('/comic/mongxinhoudehui/chapter/next-id'));
    expect(page.catalogHref, 'https://www.2026copy.com/comic/mongxinhoudehui');
    expect(page.contentKey, contentKey);
  });

  test('parses reader pages from modern script assignments', () async {
    const String cct = 'op0zzpvv.nmn.o0p';
    final String contentKey = _encryptReaderPayload(cct, <Object?>[
      <String, Object?>{'url': 'https://cdn.example.com/reader/modern.jpg'},
    ]);
    final String html =
        '''
<!DOCTYPE html>
<html lang="zh-hant">
  <head>
    <title>夢醒後的灰 - 第06話 - 拷貝漫畫 拷贝漫画</title>
  </head>
  <body>
    <h4 class="header">夢醒後的灰/第06話</h4>
    <div class="container-fluid comicContent">
      <div class="container comic-size-1">
        <ul class="comicContent-list comic-size-1"></ul>
      </div>
    </div>
    <div class="comicContent-footer-txt"><span>第7 / 7話</span></div>
    <script>
      const cct = "$cct";
      window.contentKey = `$contentKey`;
    </script>
  </body>
</html>
''';

    final ReaderPageData page =
        await parser.parsePage(
              Uri.parse(
                'https://www.2026copy.com/comic/mongxinhoudehui/chapter/demo-modern',
              ),
              html,
            )
            as ReaderPageData;

    expect(page.contentKey, contentKey);
    expect(page.imageUrls, <String>[
      'https://cdn.example.com/reader/modern.jpg',
    ]);
  });

  test('parses detail fixture and chapter endpoint payload together', () async {
    final String html = await File(fixturePath('series.html')).readAsString();
    final String encryptedResults = _encryptChapterPayload(
      'op0zzpvv.nzn.ocp',
      <String, Object?>{
        'build': <String, Object?>{
          'path_word': 'modujingbingdenuli',
          'type': <Object?>[
            <String, Object?>{'id': 1, 'name': '話'},
            <String, Object?>{'id': 3, 'name': '番外篇'},
          ],
        },
        'groups': <String, Object?>{
          'default': <String, Object?>{
            'path_word': 'default',
            'name': '默認',
            'chapters': <Object?>[
              <String, Object?>{
                'type': 1,
                'name': '第01话',
                'id': '52615840-10a4-11e9-b68d-00163e0ca5bd',
              },
              <String, Object?>{
                'type': 1,
                'name': '第02话',
                'id': 'c2d8f146-17b6-11e9-bfa4-00163e0ca5bd',
              },
            ],
          },
          'extra': <String, Object?>{
            'path_word': 'extra',
            'name': '番外篇',
            'chapters': <Object?>[
              <String, Object?>{
                'type': 3,
                'name': '出张版',
                'id': '956b5976-0e17-11ea-b01f-00163e0ca5bd',
              },
            ],
          },
        },
      },
    );

    final DetailPageData page =
        await parser.parsePage(
              Uri.parse('https://www.2026copy.com/comic/modujingbingdenuli'),
              html,
              loadDetailChapterResults: (DetailChapterRequest request) async {
                expect(request.slug, 'modujingbingdenuli');
                expect(request.dnt, '3');
                expect(request.ccz, 'op0zzpvv.nzn.ocp');
                return encryptedResults;
              },
            )
            as DetailPageData;

    expect(page.title, '魔都精兵的奴隸');
    expect(page.authors, '竹村洋平 / タカヒロ');
    expect(page.updatedAt, '2026-01-05');
    expect(page.status, '連載中');
    expect(page.summary, contains('在未來，日本各地出現'));
    expect(
      page.tags.map((LinkAction item) => item.label),
      containsAll(<String>['冒險', '奇幻']),
    );
    expect(page.comicId, '155edbf2-10a4-11e9-828f-00163e0ca5bd');
    expect(page.isCollected, isFalse);
    expect(
      page.startReadingHref,
      contains(
        '/comic/modujingbingdenuli/chapter/52615840-10a4-11e9-b68d-00163e0ca5bd',
      ),
    );
    expect(page.chapterGroups, hasLength(2));
    expect(page.chapterGroups.first.label, '全部');
    expect(page.chapterGroups.first.chapters, hasLength(2));
    expect(page.chapterGroups.last.label, '番外篇');
    expect(page.chapterGroups.last.chapters.single.label, '出张版');
    expect(page.chapters, hasLength(3));
  });

  test('parses detail fallback with modern JS quoting', () async {
    const String ccz = 'op0zzpvv.nzn.ocp';
    final String encryptedResults = _encryptChapterPayload(
      ccz,
      <String, Object?>{
        'build': <String, Object?>{
          'path_word': 'demo-modern',
          'type': <Object?>[
            <String, Object?>{'id': 1, 'name': '話'},
          ],
        },
        'groups': <String, Object?>{
          'default': <String, Object?>{
            'path_word': 'default',
            'name': '默認',
            'chapters': <Object?>[
              <String, Object?>{
                'type': 1,
                'name': '第01話',
                'id': 'chapter-modern-1',
              },
            ],
          },
        },
      },
    );
    const String html =
        '''
<!DOCTYPE html>
<html lang="zh-hant">
  <head>
    <title>測試作品 - 拷貝漫畫 拷贝漫画</title>
  </head>
  <body>
    <div class="comicParticulars-title"></div>
    <h6 title="測試作品"></h6>
    <input id="dnt" value="3">
    <a class="comicParticulars-botton collect" onclick='collect("comic-modern-id")'>
      已在書架
    </a>
    <script>
      const ccz = "$ccz";
    </script>
  </body>
</html>
''';

    final DetailPageData page =
        await parser.parsePage(
              Uri.parse('https://www.2026copy.com/comic/demo-modern'),
              html,
              loadDetailChapterResults: (DetailChapterRequest request) async {
                expect(request.slug, 'demo-modern');
                expect(request.dnt, '3');
                expect(request.ccz, ccz);
                return encryptedResults;
              },
            )
            as DetailPageData;

    expect(page.comicId, 'comic-modern-id');
    expect(page.isCollected, isTrue);
    expect(page.chapterGroups, hasLength(1));
    expect(
      page.chapterGroups.first.chapters.first.href,
      contains('chapter-modern-1'),
    );
  });

  test('parses topic index and topic detail pages', () async {
    const String topicIndexHtml = '''
<!DOCTYPE html>
<html lang="zh-hant">
  <head>
    <title>專題 - 拷貝漫畫 拷贝漫画</title>
  </head>
  <body>
    <main class="content-box">
      <div class="specialContent comic">
        <div class="specialContentImage">
          <a href="/topic/demo-topic-a">
            <img src="https://example.com/topic-a.jpg" alt="">
          </a>
          <span class="specialContentImageSpan">專題 A</span>
        </div>
        <div class="specialContentTextContent">推薦摘要 A</div>
        <div class="specialContentButton">
          <span class="specialContentButtonTime">2026-03-01</span>
        </div>
      </div>
      <div class="specialContent comic">
        <div class="specialContentImage">
          <a href="/topic/demo-topic-b">
            <img src="https://example.com/topic-b.jpg" alt="">
          </a>
          <span class="specialContentImageSpan">專題 B</span>
        </div>
      </div>
      <ul class="page-all">
        <li class="page-all-item active">
          <a href="/topic?offset=0">1</a>
        </li>
      </ul>
    </main>
  </body>
</html>
''';
    const String topicDetailHtml = '''
<!DOCTYPE html>
<html lang="zh-hant">
  <head>
    <title>秋番漫畫專題 - 拷貝漫畫 拷贝漫画</title>
  </head>
  <body>
    <main class="container specialDetail">
      <div class="specialDetailTitle">
        <div class="specialDetailTitleFlex">
          <span>秋番漫畫專題</span>
          <span>2026-03-01</span>
        </div>
      </div>
      <div class="row">
        <div class="col-6 specialDetailItem">
          <div class="specialDetailItemHeaderImage">
            <a href="/comic/demo-a">
              <img src="https://example.com/a.jpg" alt="">
            </a>
          </div>
          <p class="specialDetailItemHeaderContentName twoLines">
            <a href="/comic/demo-a">作品 A</a>
          </p>
        </div>
        <div class="col-6 specialDetailItem">
          <div class="specialDetailItemHeaderImage">
            <a href="/comic/demo-b">
              <img src="https://example.com/b.jpg" alt="">
            </a>
          </div>
          <p class="specialDetailItemHeaderContentName twoLines">
            <a href="/comic/demo-b">作品 B</a>
          </p>
        </div>
      </div>
    </main>
  </body>
</html>
''';

    final DiscoverPageData topicIndex =
        await parser.parsePage(
              Uri.parse('https://www.2026copy.com/topic'),
              topicIndexHtml,
            )
            as DiscoverPageData;
    final DiscoverPageData topicDetail =
        await parser.parsePage(
              Uri.parse('https://www.2026copy.com/topic/demo-topic-a'),
              topicDetailHtml,
            )
            as DiscoverPageData;

    expect(topicIndex.items, hasLength(2));
    expect(topicIndex.items.first.badge, '專題');
    expect(topicIndex.pager.currentLabel, '1');

    expect(topicDetail.title, '秋番漫畫專題');
    expect(topicDetail.items, hasLength(2));
    expect(
      topicDetail.items.first.href,
      'https://www.2026copy.com/comic/demo-a',
    );
  });

  test('parses recommend and newest pages as discover pages', () async {
    const String correlationHtml = '''
<!DOCTYPE html>
<html lang="zh-hant">
  <head>
    <title>編輯推薦 - 拷貝漫畫 拷贝漫画</title>
  </head>
  <body>
    <div class="container correlationList">
      <div class="row">
        <div class="col-auto exemptComic_Item">
          <a href="/comic/demo-a">
            <img src="https://example.com/a.jpg" alt="">
          </a>
          <div class="exemptComicItem-txt-box">
            <div class="threeLines" title="推薦作品A"></div>
          </div>
        </div>
        <div class="col-auto exemptComic_Item">
          <a href="/comic/demo-b">推薦作品B</a>
        </div>
      </div>
    </div>
    <ul class="page-all">
      <li class="page-all-item active">
        <a href="/recommend?offset=0">1</a>
      </li>
    </ul>
  </body>
</html>
''';

    final DiscoverPageData recommend =
        await parser.parsePage(
              Uri.parse('https://www.2026copy.com/recommend'),
              correlationHtml,
            )
            as DiscoverPageData;
    final DiscoverPageData newest =
        await parser.parsePage(
              Uri.parse('https://www.2026copy.com/newest'),
              correlationHtml,
            )
            as DiscoverPageData;

    expect(recommend.items, hasLength(2));
    expect(recommend.items.first.title, '推薦作品A');
    expect(recommend.pager.currentLabel, '1');

    expect(newest.items, hasLength(2));
    expect(newest.items.last.href, 'https://www.2026copy.com/comic/demo-b');
  });
}

String _encryptChapterPayload(String ccz, Map<String, Object?> payload) {
  const String prefix = '1234567890abcdef';
  final PaddedBlockCipher cipher = PaddedBlockCipherImpl(
    PKCS7Padding(),
    CBCBlockCipher(AESEngine()),
  );
  cipher.init(
    true,
    PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
      ParametersWithIV<KeyParameter>(
        KeyParameter(Uint8List.fromList(utf8.encode(ccz))),
        Uint8List.fromList(utf8.encode(prefix)),
      ),
      null,
    ),
  );

  final Uint8List encrypted = cipher.process(
    Uint8List.fromList(utf8.encode(jsonEncode(payload))),
  );
  return '$prefix${_hexEncode(encrypted)}';
}

String _encryptReaderPayload(String cct, List<Object?> payload) {
  const String prefix = '1234567890abcdef';
  final PaddedBlockCipher cipher = PaddedBlockCipherImpl(
    PKCS7Padding(),
    CBCBlockCipher(AESEngine()),
  );
  cipher.init(
    true,
    PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
      ParametersWithIV<KeyParameter>(
        KeyParameter(Uint8List.fromList(utf8.encode(cct))),
        Uint8List.fromList(utf8.encode(prefix)),
      ),
      null,
    ),
  );

  final Uint8List encrypted = cipher.process(
    Uint8List.fromList(utf8.encode(jsonEncode(payload))),
  );
  return '$prefix${_hexEncode(encrypted)}';
}

String _hexEncode(List<int> bytes) {
  final StringBuffer buffer = StringBuffer();
  for (final int byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
