import 'package:easy_copy/models/app_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReaderPreferences', () {
    test('enables chapter comments by default', () {
      const ReaderPreferences preferences = ReaderPreferences();

      expect(preferences.showChapterComments, isTrue);
      expect(
        ReaderPreferences.fromJson(const <String, Object?>{})
            .showChapterComments,
        isTrue,
      );
    });

    test('serializes chapter comment preference', () {
      final ReaderPreferences preferences = const ReaderPreferences().copyWith(
        showChapterComments: false,
      );

      final ReaderPreferences restored = ReaderPreferences.fromJson(
        preferences.toJson(),
      );

      expect(restored.showChapterComments, isFalse);
    });
  });
}
