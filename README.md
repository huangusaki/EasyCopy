# EasyCopy

Flutter client that keeps the original desktop page hidden and renders a mobile-first reading UI for `https://www.2026copy.com/`.

## Development

- Install Flutter 3.35+ with Dart 3.9+
- Run `flutter pub get`
- Start locally with `flutter run`
- Build Android APK with `.\build_arm64.ps1`
- Build standalone `arm64-v8a` APK with `.\build_apk_arm64_v8a.ps1`
  - Optional: `.\build_apk_arm64_v8a.ps1 -Obfuscate`

## Verification

- `flutter analyze`
- `flutter test`

## Notes

- The app keeps the existing Android/iOS internal identifiers to avoid high-risk platform renames.
- WebView now stays behind the native shell and is only used to fetch and transform page data.
