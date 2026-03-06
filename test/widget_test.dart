import 'package:easy_copy/config/app_config.dart';
import 'package:easy_copy/easy_copy_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('EasyCopyApp exposes the updated application title', (
    WidgetTester tester,
  ) async {
    const placeholder = SizedBox(key: Key('placeholder-home'));

    await tester.pumpWidget(const EasyCopyApp(home: placeholder));

    final MaterialApp materialApp = tester.widget<MaterialApp>(
      find.byType(MaterialApp),
    );
    expect(materialApp.title, AppConfig.appName);
    expect(find.byKey(const Key('placeholder-home')), findsOneWidget);
  });
}
