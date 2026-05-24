import 'package:easy_copy/easy_copy_app.dart';
import 'package:easy_copy/services/app_preferences_controller.dart';
import 'package:easy_copy/services/wallpaper_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final AppPreferencesController preferencesController =
      AppPreferencesController.instance;
  await preferencesController.ensureInitialized();
  await WallpaperStorage.instance.ensureReady();
  runApp(EasyCopyApp(preferencesController: preferencesController));
}
