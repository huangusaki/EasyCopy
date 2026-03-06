# EasyCopy

Flutter client that keeps the original desktop page hidden and renders a mobile-first reading UI for `https://www.2026copy.com/`.

## Development

- Install Flutter 3.35+ with Dart 3.9+
- Run `flutter pub get`
- Start locally with `flutter run`
- Build Android APK with `.\build_arm64.ps1`

## Verification

- `flutter analyze`
- `flutter test`

## Notes

- The app keeps the existing Android/iOS internal identifiers to avoid high-risk platform renames.
- WebView now stays behind the native shell and is only used to fetch and transform page data.
