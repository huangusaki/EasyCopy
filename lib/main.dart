import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:reader/app.dart';
import 'package:reader/services/app_preferences_controller.dart';
import 'package:reader/services/app_runtime.dart';
import 'package:reader/services/chinese_converter.dart';
import 'package:reader/services/wallpaper_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppRuntime.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final AppPreferencesController preferencesController =
      AppPreferencesController.instance;
  await preferencesController.ensureInitialized();
  await WallpaperStorage.instance.ensureReady();

  // 初始化繁简转换服务
  final ChineseConverter converter = ChineseConverter.instance;
  await converter.initializeWithMode(
    preferencesController.chineseConversionMode,
  );

  runApp(AppRoot(preferencesController: preferencesController));
}
