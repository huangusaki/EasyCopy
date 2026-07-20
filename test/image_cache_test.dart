import 'package:flutter_test/flutter_test.dart';
import 'package:reader/services/image_cache.dart';

void main() {
  group('readerPrefetchUrlsAfter', () {
    test('selects the next ten pages after the current page', () {
      final List<String> urls = List<String>.generate(
        20,
        (int index) => 'https://example.com/${index + 1}.jpg',
      );

      expect(
        readerPrefetchUrlsAfter(urls, currentIndex: 8),
        urls.sublist(9, 19),
      );
      expect(readerPrefetchLimit, 10);
      expect(readerPriorityPrefetchLimit, 2);
      expect(readerPrefetchConcurrency, 5);
    });

    test('filters invalid and duplicate URLs before applying the limit', () {
      final List<String> urls = <String>[
        'file:///local/1.jpg',
        ' https://example.com/1.jpg ',
        'https://example.com/1.jpg',
        '',
        'http://example.com/2.jpg',
        'ftp://example.com/3.jpg',
        'https://example.com/4.jpg',
      ];

      expect(readerPrefetchUrlsAfter(urls, currentIndex: -1), <String>[
        'https://example.com/1.jpg',
        'http://example.com/2.jpg',
        'https://example.com/4.jpg',
      ]);
    });

    test('returns an empty window after the last page', () {
      expect(
        readerPrefetchUrlsAfter(const <String>[
          'https://example.com/1.jpg',
        ], currentIndex: 0),
        isEmpty,
      );
    });
  });
}
