# Build APK for arm64-v8a
Write-Host "Building Release APK for arm64-v8a..." -ForegroundColor Green

flutter build apk --release --target-platform android-arm64

if ($?) {
    Write-Host "Build Success!" -ForegroundColor Green
    Write-Host "APK Location: build\app\outputs\flutter-apk\app-release.apk" -ForegroundColor Yellow
} else {
    Write-Host "Build Failed!" -ForegroundColor Red
    exit 1
}
