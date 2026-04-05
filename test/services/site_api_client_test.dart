import 'dart:convert';

import 'package:easy_copy/services/key_value_store.dart';
import 'package:easy_copy/services/site_api_client.dart';
import 'package:easy_copy/services/site_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SiteApiClient comments', () {
    late SiteSession session;
    late _MemoryKeyValueStore store;

    setUp(() {
      store = _MemoryKeyValueStore();
      session = SiteSession(store: store);
    });

    test('loads chapter comments with avatar and optional like count', () async {
      final SiteApiClient client = SiteApiClient(
        session: session,
        client: MockClient((http.Request request) async {
          expect(request.method, 'GET');
          expect(request.url.host, 'api.mangacopy.com');
          expect(request.url.path, '/api/v3/roasts');
          expect(request.url.queryParameters['chapter_id'], 'chapter-123');
          expect(request.url.queryParameters['limit'], '3');
          expect(request.url.queryParameters['offset'], '0');
          return http.Response(
            jsonEncode(<String, Object?>{
              'code': 200,
              'message': 'ok',
              'results': <String, Object?>{
                'total': 2,
                'list': <Map<String, Object?>>[
                  <String, Object?>{
                    'id': 101,
                    'comment': '第一条评论',
                    'user_avatar': 'https://example.com/a.png',
                    'like_count': 7,
                  },
                  <String, Object?>{
                    'id': 102,
                    'comment': '第二条评论',
                    'user_avatar': 'https://example.com/b.png',
                  },
                ],
              },
            }),
            200,
            headers: const <String, String>{
              'content-type': 'application/json',
            },
          );
        }),
      );

      final feed = await client.loadChapterComments(
        chapterId: 'chapter-123',
        limit: 3,
      );

      expect(feed.total, 2);
      expect(feed.comments, hasLength(2));
      expect(feed.comments.first.id, '101');
      expect(feed.comments.first.message, '第一条评论');
      expect(feed.comments.first.avatarUrl, 'https://example.com/a.png');
      expect(feed.comments.first.likeCount, 7);
      expect(feed.comments.last.likeCount, isNull);
    });

    test('loads chapter comments with pagination offset', () async {
      final SiteApiClient client = SiteApiClient(
        session: session,
        client: MockClient((http.Request request) async {
          expect(request.method, 'GET');
          expect(request.url.host, 'api.mangacopy.com');
          expect(request.url.path, '/api/v3/roasts');
          expect(request.url.queryParameters['chapter_id'], 'chapter-456');
          expect(request.url.queryParameters['limit'], '40');
          expect(request.url.queryParameters['offset'], '80');
          return http.Response(
            jsonEncode(<String, Object?>{
              'code': 200,
              'message': 'ok',
              'results': <String, Object?>{
                'total': 120,
                'list': <Map<String, Object?>>[
                  <String, Object?>{
                    'id': 201,
                    'comment': '分页评论',
                  },
                ],
              },
            }),
            200,
            headers: const <String, String>{
              'content-type': 'application/json',
            },
          );
        }),
      );

      final feed = await client.loadChapterComments(
        chapterId: 'chapter-456',
        limit: 40,
        offset: 80,
      );

      expect(feed.total, 120);
      expect(feed.comments, hasLength(1));
      expect(feed.comments.single.id, '201');
      expect(feed.comments.single.message, '分页评论');
    });

    test('posts chapter comment with auth token and roast payload', () async {
      await session.saveToken(
        'token-123',
        cookies: const <String, String>{'token': 'token-123', 'user_id': 'u-1'},
      );

      final SiteApiClient client = SiteApiClient(
        session: session,
        client: MockClient((http.Request request) async {
          expect(request.method, 'POST');
          expect(request.url.host, 'api.mangacopy.com');
          expect(request.url.path, '/api/v3/member/roast');
          expect(request.headers['authorization'], 'Token token-123');
          expect(request.bodyFields['chapter_id'], 'chapter-456');
          expect(request.bodyFields['roast'], '尾页评论');
          expect(request.bodyFields['_update'], 'true');
          return http.Response(
            jsonEncode(<String, Object?>{
              'code': 200,
              'message': 'ok',
            }),
            200,
            headers: const <String, String>{
              'content-type': 'application/json',
            },
          );
        }),
      );

      await client.postChapterComment(
        chapterId: 'chapter-456',
        content: '尾页评论',
      );
    });
  });
}

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
