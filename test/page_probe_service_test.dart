import 'dart:io';
import 'dart:convert';

import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/services/page_probe_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('page probe recognizes homepage and detail pages', () async {
    final String homeHtml = await File('homepage.html').readAsString();
    final String detailHtml = await File('series.html').readAsString();
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
    final String readerHtml = await File('chapter.html').readAsString();
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
}
