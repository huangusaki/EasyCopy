import 'dart:async';
import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:reader/models/app_preferences.dart';
import 'package:reader/services/app_preferences_controller.dart';
import 'package:reader/services/wallpaper_storage.dart';
import 'package:reader/widgets/profile_page_view.dart';

WallpaperEditingActions buildWallpaperActions({
  required AppPreferencesController preferencesController,
  required void Function(String message) showError,
}) {
  return WallpaperEditingActions(
    pickImage: () => _pickAndApplyWallpaper(
      preferencesController: preferencesController,
      showError: showError,
    ),
    clearImage: () => _clearWallpaper(preferencesController),
    previewPreferences: (WallpaperPreferences value) {
      unawaited(
        preferencesController.updateWallpaperPreferences(
          (_) => value,
          persist: false,
        ),
      );
    },
    commitPreferences: (WallpaperPreferences value) {
      unawaited(preferencesController.updateWallpaperPreferences((_) => value));
    },
  );
}

Future<void> _pickAndApplyWallpaper({
  required AppPreferencesController preferencesController,
  required void Function(String message) showError,
}) async {
  final ImagePicker picker = ImagePicker();
  XFile? picked;
  try {
    picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
    );
  } catch (error) {
    showError('选择图片失败：$error');
    return;
  }
  if (picked == null) {
    return;
  }
  try {
    final WallpaperPreferences previous =
        preferencesController.wallpaperPreferences;
    await WallpaperStorage.instance.ensureReady();
    final String savedFileName = await WallpaperStorage.instance.saveImage(
      File(picked.path),
    );
    await preferencesController.updateWallpaperPreferences(
      (WallpaperPreferences current) => current.copyWith(
        imageFileName: savedFileName,
        enabled: true,
        cropLeft: 0,
        cropTop: 0,
        cropWidth: 1,
        cropHeight: 1,
      ),
    );
    unawaited(WallpaperStorage.instance.pruneExcept(savedFileName));
    if (previous.imageFileName.isNotEmpty &&
        previous.imageFileName != savedFileName) {
      unawaited(WallpaperStorage.instance.deleteFile(previous.imageFileName));
    }
  } catch (error) {
    showError('保存壁纸失败：$error');
  }
}

void _clearWallpaper(AppPreferencesController preferencesController) {
  final WallpaperPreferences previous =
      preferencesController.wallpaperPreferences;
  unawaited(
    preferencesController.updateWallpaperPreferences(
      (WallpaperPreferences current) => current.copyWith(
        imageFileName: '',
        enabled: false,
        cropLeft: 0,
        cropTop: 0,
        cropWidth: 1,
        cropHeight: 1,
      ),
    ),
  );
  if (previous.imageFileName.isNotEmpty) {
    unawaited(WallpaperStorage.instance.deleteFile(previous.imageFileName));
  }
}
