import 'dart:convert';

import 'package:easy_copy/services/key_value_store.dart';
import 'package:easy_copy/services/site_api_client.dart';
import 'package:easy_copy/services/site_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<String?> read(String key) async {
    return _values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

void main() {
  http.Response jsonResponse(Map<String, Object?> payload) {
    return http.Response.bytes(
      utf8.encode(jsonEncode(payload)),
      200,
      headers: const <String, String>{
        'content-type': 'application/json; charset=utf-8',
      },
    );
  }

  test(
    'loadProfile sends session cookies and parses kb history response',
    () async {
      final SiteSession session = SiteSession(
        store: _MemoryKeyValueStore(),
        now: () => DateTime(2026, 3, 7, 9),
      );
      await session.saveToken(
        'token_123',
        cookies: const <String, String>{'token': 'token_123'},
      );

      final List<String> requestedPaths = <String>[];
      final SiteApiClient client = SiteApiClient(
        session: session,
        client: MockClient((http.Request request) async {
          requestedPaths.add(request.url.path);
          expect(request.headers['cookie'], 'token=token_123');

          switch (request.url.path) {
            case '/api/v2/web/user/info':
              return jsonResponse(<String, Object?>{
                'code': 200,
                'results': <String, Object?>{
                  'user_id': 'user-42',
                  'username': 'reader_demo',
                  'nickname': '读者演示',
                  'avatar': 'https://img.example/avatar.png',
                  'datetime_created': '2026-03-01T08:00:00Z',
                },
              });
            case '/api/v3/member/collect/comics':
              return jsonResponse(<String, Object?>{
                'code': 200,
                'results': <String, Object?>{
                  'list': <Object?>[
                    <String, Object?>{
                      'comic': <String, Object?>{
                        'name': '收藏作品',
                        'path_word': 'favorite-comic',
                        'cover': 'https://img.example/favorite.jpg',
                      },
                    },
                  ],
                },
              });
            case '/api/kb/web/browses':
              return jsonResponse(<String, Object?>{
                'code': 200,
                'results': <String, Object?>{
                  'list': <Object?>[
                    <String, Object?>{
                      'last_chapter_id': 'chapter-42',
                      'last_chapter_name': '第42话',
                      'datetime_created': '2026-03-07T08:00:00Z',
                      'comic': <String, Object?>{
                        'name': '历史作品',
                        'path_word': 'history-comic',
                        'cover': 'https://img.example/history.jpg',
                      },
                    },
                  ],
                },
              });
            default:
              fail('Unexpected path: ${request.url.path}');
          }
        }),
      );

      final page = await client.loadProfile();

      expect(page.isLoggedIn, isTrue);
      expect(page.user?.username, 'reader_demo');
      expect(
        page.collections.single.href,
        'https://www.2026copy.com/comic/favorite-comic',
      );
      expect(page.history.single.chapterLabel, '第42话');
      expect(
        page.history.single.chapterHref,
        'https://www.2026copy.com/comic/history-comic/chapter/chapter-42',
      );
      expect(
        page.continueReading?.chapterHref,
        page.history.single.chapterHref,
      );
      expect(requestedPaths, contains('/api/kb/web/browses'));
      expect(requestedPaths, isNot(contains('/api/v2/web/browses')));
      expect(session.userId, 'user-42');
    },
  );

  test('loadProfile tolerates optional endpoint failures', () async {
    final SiteSession session = SiteSession(
      store: _MemoryKeyValueStore(),
      now: () => DateTime(2026, 3, 7, 10),
    );
    await session.saveToken(
      'token_456',
      cookies: const <String, String>{'token': 'token_456'},
    );

    final SiteApiClient client = SiteApiClient(
      session: session,
      client: MockClient((http.Request request) async {
        switch (request.url.path) {
          case '/api/v2/web/user/info':
            return jsonResponse(<String, Object?>{
              'code': 200,
              'results': <String, Object?>{
                'user_id': 'user-99',
                'username': 'fallback_user',
              },
            });
          case '/api/v3/member/collect/comics':
          case '/api/kb/web/browses':
          case '/api/v2/web/browses':
            return http.Response('<html>maintenance</html>', 404);
          default:
            fail('Unexpected path: ${request.url.path}');
        }
      }),
    );

    final page = await client.loadProfile();

    expect(page.isLoggedIn, isTrue);
    expect(page.user?.username, 'fallback_user');
    expect(page.collections, isEmpty);
    expect(page.history, isEmpty);
    expect(page.continueReading, isNull);
  });
}
