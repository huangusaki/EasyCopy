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
