import 'package:easy_copy/models/app_preferences.dart';
import 'package:easy_copy/config/app_config.dart';
import 'package:easy_copy/easy_copy_app.dart';
import 'package:easy_copy/services/app_preferences_controller.dart';
import 'package:easy_copy/services/app_preferences_store.dart';
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

  testWidgets('EasyCopyApp reacts to theme preference changes', (
    WidgetTester tester,
  ) async {
    final _MemoryAppPreferencesStore store = _MemoryAppPreferencesStore();
    final AppPreferencesController controller = AppPreferencesController(
      store: store,
    );
    await controller.ensureInitialized();

    await tester.pumpWidget(
      EasyCopyApp(
        home: const SizedBox(key: Key('theme-home')),
        preferencesController: controller,
      ),
    );

    MaterialApp materialApp = tester.widget<MaterialApp>(
      find.byType(MaterialApp),
    );
    expect(materialApp.themeMode, ThemeMode.system);

    await controller.setThemePreference(AppThemePreference.dark);
    await tester.pump();
    materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.themeMode, ThemeMode.dark);

    await controller.setThemePreference(AppThemePreference.light);
    await tester.pump();
    materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.themeMode, ThemeMode.light);
  });
}

class _MemoryAppPreferencesStore extends AppPreferencesStore {
  AppPreferences _preferences = const AppPreferences();

  @override
  Future<AppPreferences> read() async {
    return _preferences;
  }

  @override
  Future<void> write(AppPreferences preferences) async {
    _preferences = preferences;
  }
}
