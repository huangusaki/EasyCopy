import 'package:easy_copy/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolvePath builds URLs against the new domain', () {
    expect(
      AppConfig.resolvePath('/rank').toString(),
      'https://www.2026copy.com/rank',
    );
  });

  test('isAllowedNavigationUri blocks external domains and schemes', () {
    expect(
      AppConfig.isAllowedNavigationUri(
        Uri.parse('https://www.2026copy.com/comics'),
      ),
      isTrue,
    );
    expect(
      AppConfig.isAllowedNavigationUri(Uri.parse('https://example.com')),
      isFalse,
    );
    expect(
      AppConfig.isAllowedNavigationUri(Uri.parse('mailto:test@example.com')),
      isFalse,
    );
    expect(AppConfig.isAllowedNavigationUri(Uri.parse('about:blank')), isTrue);
  });

  test('tabIndexForUri keeps major site areas mapped to navigation tabs', () {
    expect(tabIndexForUri(Uri.parse('https://www.2026copy.com/')), 0);
    expect(tabIndexForUri(Uri.parse('https://www.2026copy.com/comic/demo')), 1);
    expect(tabIndexForUri(Uri.parse('https://www.2026copy.com/rank/day')), 2);
    expect(
      tabIndexForUri(
        Uri.parse('https://www.2026copy.com/web/login?url=person/home'),
      ),
      3,
    );
  });
}
