import 'dart:io';
import 'dart:convert';

import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/services/page_probe_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String fixturePath(String name) {
  return 'test${Platform.pathSeparator}fixtures${Platform.pathSeparator}'
      'site${Platform.pathSeparator}$name';
}

void main() {
  test('page probe recognizes homepage and detail pages', () async {
    final String homeHtml = await File(
      fixturePath('homepage.html'),
    ).readAsString();
    final String detailHtml = await File(
      fixturePath('series.html'),
    ).readAsString();
    final PageProbeService service = PageProbeService(
      client: MockClient((http.Request request) async {
        if (request.url.path == '/') {
          return http.Response.bytes(utf8.encode(homeHtml), 200);
        }
        return http.Response.bytes(utf8.encode(detailHtml), 200);
      }),
      now: () => DateTime(2026, 3, 6, 12),
      userAgent: 'test-agent',
    );

    final PageProbeResult home = await service.probe(
      Uri.parse('https://www.2026copy.com/'),
    );
    final PageProbeResult detail = await service.probe(
      Uri.parse('https://www.2026copy.com/comic/example'),
    );

    expect(home.pageType, EasyCopyPageType.home);
    expect(home.fingerprint.split('::').last, isNot('0'));

    final List<String> detailParts = detail.fingerprint.split('::');
    expect(detail.pageType, EasyCopyPageType.detail);
    expect(detailParts, hasLength(6));
    expect(detailParts[1], isNotEmpty);
    expect(detailParts[2], isNotEmpty);
  });

  test('page probe extracts reader contentKey fingerprint', () async {
    final String readerHtml = await File(
      fixturePath('chapter.html'),
    ).readAsString();
    final PageProbeService service = PageProbeService(
      client: MockClient((http.Request request) async {
        return http.Response.bytes(utf8.encode(readerHtml), 200);
      }),
      now: () => DateTime(2026, 3, 6, 12),
      userAgent: 'test-agent',
    );

    final PageProbeResult reader = await service.probe(
      Uri.parse(
        'https://www.2026copy.com/comic/modujingbingdenuli/chapter/52615840-10a4-11e9-b68d-00163e0ca5bd',
      ),
    );

    final List<String> parts = reader.fingerprint.split('::');
    expect(reader.pageType, EasyCopyPageType.reader);
    expect(parts, hasLength(4));
    expect(parts[1], contains('魔都精兵的奴隸'));
    expect(parts[3], startsWith('nFRYsol9gpyEe16B'));
  });

  test(
    'page probe extracts reader contentKey fingerprint from modern assignment',
    () async {
      const String readerHtml = '''
<!DOCTYPE html>
<html lang="zh-hant">
  <head>
    <title>測試閱讀頁 - 拷貝漫畫 拷贝漫画</title>
  </head>
  <body>
    <h4 class="header">測試作品/第01話</h4>
    <div class="comicContent-footer-txt"><span>第1 / 1話</span></div>
    <script>
      const contentKey = "modern-reader-key";
    </script>
  </body>
</html>
''';
      final PageProbeService service = PageProbeService(
        client: MockClient((http.Request request) async {
          return http.Response.bytes(utf8.encode(readerHtml), 200);
        }),
        now: () => DateTime(2026, 3, 6, 12),
        userAgent: 'test-agent',
      );

      final PageProbeResult reader = await service.probe(
        Uri.parse('https://www.2026copy.com/comic/demo/chapter/modern'),
      );

      final List<String> parts = reader.fingerprint.split('::');
      expect(reader.pageType, EasyCopyPageType.reader);
      expect(parts, hasLength(4));
      expect(parts[3], 'modern-reader-key');
    },
  );

  test('page probe fingerprints discover filters and comic cards', () async {
    final String discoverHtml = await File(
      fixturePath('comics.html'),
    ).readAsString();
    final PageProbeService service = PageProbeService(
      client: MockClient((http.Request request) async {
        return http.Response.bytes(utf8.encode(discoverHtml), 200);
      }),
      now: () => DateTime(2026, 3, 6, 12),
      userAgent: 'test-agent',
    );

    final PageProbeResult discover = await service.probe(
      Uri.parse('https://www.2026copy.com/comics?ordering=-datetime_updated'),
    );

    expect(discover.pageType, EasyCopyPageType.discover);
    expect(
      discover.fingerprint,
      startsWith('/comics::ordering=-datetime_updated::'),
    );
    expect(discover.fingerprint, contains('全部'));
    expect(discover.fingerprint, contains('更新時間↓'));
    expect(
      discover.fingerprint,
      contains(
        'https://www.2026copy.com/comic/huanxiangnanzibianchenglexianshizhuyizhe',
      ),
    );
    expect(discover.fingerprint, endsWith('::21'));
  });

  test(
    'page probe treats recommend and newest routes as discover pages',
    () async {
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
      final PageProbeService service = PageProbeService(
        client: MockClient((http.Request request) async {
          return http.Response.bytes(utf8.encode(correlationHtml), 200);
        }),
        now: () => DateTime(2026, 3, 6, 12),
        userAgent: 'test-agent',
      );

      final PageProbeResult recommend = await service.probe(
        Uri.parse('https://www.2026copy.com/recommend'),
      );
      final PageProbeResult newest = await service.probe(
        Uri.parse('https://www.2026copy.com/newest'),
      );

      expect(recommend.pageType, EasyCopyPageType.discover);
      expect(recommend.fingerprint, startsWith('/recommend::'));
      expect(
        recommend.fingerprint,
        contains('https://www.2026copy.com/comic/demo-a'),
      );
      expect(recommend.fingerprint, endsWith('::2'));

      expect(newest.pageType, EasyCopyPageType.discover);
      expect(newest.fingerprint, startsWith('/newest::'));
      expect(
        newest.fingerprint,
        contains('https://www.2026copy.com/comic/demo-b'),
      );
      expect(newest.fingerprint, endsWith('::2'));
    },
  );

  test('page probe treats topic routes as discover pages', () async {
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
    <div class="titleImg swiper">
      <img src="https://example.com/topic-cover.jpg" alt="">
    </div>
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
    final PageProbeService service = PageProbeService(
      client: MockClient((http.Request request) async {
        if (request.url.path == '/topic') {
          return http.Response.bytes(utf8.encode(topicIndexHtml), 200);
        }
        return http.Response.bytes(utf8.encode(topicDetailHtml), 200);
      }),
      now: () => DateTime(2026, 3, 6, 12),
      userAgent: 'test-agent',
    );

    final PageProbeResult topicIndex = await service.probe(
      Uri.parse('https://www.2026copy.com/topic'),
    );
    final PageProbeResult topicDetail = await service.probe(
      Uri.parse('https://www.2026copy.com/topic/demo-topic-a'),
    );

    expect(topicIndex.pageType, EasyCopyPageType.discover);
    expect(topicIndex.fingerprint, startsWith('/topic::::1::'));
    expect(
      topicIndex.fingerprint,
      contains('https://www.2026copy.com/topic/demo-topic-a'),
    );
    expect(topicIndex.fingerprint, endsWith('::2'));

    expect(topicDetail.pageType, EasyCopyPageType.discover);
    expect(
      topicDetail.fingerprint,
      startsWith('/topic/demo-topic-a::秋番漫畫專題::'),
    );
    expect(
      topicDetail.fingerprint,
      contains('https://www.2026copy.com/comic/demo-a'),
    );
    expect(topicDetail.fingerprint, endsWith('::2'));
  });

  test('page probe fingerprints rank tabs and ranking cards', () async {
    final String rankHtml = await File(fixturePath('rank.html')).readAsString();
    final PageProbeService service = PageProbeService(
      client: MockClient((http.Request request) async {
        return http.Response.bytes(utf8.encode(rankHtml), 200);
      }),
      now: () => DateTime(2026, 3, 6, 12),
      userAgent: 'test-agent',
    );

    final PageProbeResult rank = await service.probe(
      Uri.parse('https://www.2026copy.com/rank?type=male&table=day'),
    );

    expect(rank.pageType, EasyCopyPageType.rank);
    expect(rank.fingerprint, startsWith('/rank::'));
    expect(rank.fingerprint, contains('漫畫排行榜(男頻)'));
    expect(rank.fingerprint, contains('日榜(上升最快)'));
    expect(
      rank.fingerprint,
      contains('https://www.2026copy.com/comic/modujingbingdenuli'),
    );
    expect(rank.fingerprint, endsWith('::100'));
  });
}
