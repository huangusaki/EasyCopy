import 'package:easy_copy/easy_copy_app.dart';
import 'package:easy_copy/services/app_preferences_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final AppPreferencesController preferencesController =
      AppPreferencesController.instance;
  await preferencesController.ensureInitialized();
  runApp(EasyCopyApp(preferencesController: preferencesController));
}
