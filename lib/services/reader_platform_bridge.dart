import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:reader/models/app_preferences.dart';
import 'package:reader/utils/platform_capabilities.dart';
import 'package:window_manager/window_manager.dart';

enum ReaderVolumeKeyAction { previous, next }

class ReaderPlatformBridge {
  ReaderPlatformBridge({
    MethodChannel? methodChannel,
    EventChannel? batteryChannel,
    EventChannel? volumeKeyChannel,
  }) : _methodChannel =
           methodChannel ??
           const MethodChannel('easy_copy/reader_platform/methods'),
       _batteryChannel =
           batteryChannel ??
           const EventChannel('easy_copy/reader_platform/battery'),
       _volumeKeyChannel =
           volumeKeyChannel ??
           const EventChannel('easy_copy/reader_platform/volume_keys');

  static final ReaderPlatformBridge instance = ReaderPlatformBridge();

  final MethodChannel _methodChannel;
  final EventChannel _batteryChannel;
  final EventChannel _volumeKeyChannel;

  /// 桌面端：路由仍在阅读器内时，禁止把窗口退出全屏。
  ///
  /// 由外壳按路由维护，而不是由 ReaderScreen 的生命周期维护——切章时阅读器会被
  /// 整个卸载去渲染加载页，那次 dispose 不代表用户离开了阅读器。
  /// 只作用于 [restoreDefaultPresentation]；设置里手动关全屏走的是
  /// [applyReaderPresentation]，不受这个开关影响。
  bool retainDesktopFullscreen = false;

  bool get isAndroidSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get _isDesktop => PlatformCapabilities.isDesktop;

  bool get supportsOrientationLock =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  bool get _isRunningInTest =>
      !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  Stream<int> get batteryStream {
    if (!isAndroidSupported) {
      return const Stream<int>.empty();
    }
    return _batteryChannel.receiveBroadcastStream().map((Object? raw) {
      return ((raw as num?) ?? 0).round().clamp(0, 100);
    });
  }

  Stream<ReaderVolumeKeyAction> get volumeKeyEventStream {
    if (!isAndroidSupported) {
      return const Stream<ReaderVolumeKeyAction>.empty();
    }
    return _volumeKeyChannel.receiveBroadcastStream().map((Object? raw) {
      return (raw as String?) == 'previous'
          ? ReaderVolumeKeyAction.previous
          : ReaderVolumeKeyAction.next;
    });
  }

  Future<void> setKeepScreenOn(bool enabled) async {
    if (!isAndroidSupported) {
      return;
    }
    await _methodChannel.invokeMethod<void>('setKeepScreenOn', enabled);
  }

  Future<void> setVolumePagingEnabled(bool enabled) async {
    if (!isAndroidSupported) {
      return;
    }
    await _methodChannel.invokeMethod<void>('setVolumePagingEnabled', enabled);
  }

  Future<void> applyReaderPresentation({
    required ReaderScreenOrientation orientation,
    required bool fullscreen,
  }) async {
    if (_isDesktop) {
      await _setDesktopFullscreen(fullscreen);
      return;
    }
    if (supportsOrientationLock) {
      await SystemChrome.setPreferredOrientations(
        orientation == ReaderScreenOrientation.landscape
            ? const <DeviceOrientation>[
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]
            : const <DeviceOrientation>[DeviceOrientation.portraitUp],
      );
    }
    await SystemChrome.setEnabledSystemUIMode(
      fullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  Future<void> restoreDefaultPresentation() async {
    if (_isDesktop) {
      // 路由还在阅读器里就别退全屏：切章时 ReaderScreen 会被整个卸载去渲染加载页，
      // 它 dispose 里的这次恢复会把窗口退出全屏，等新章节挂载后再进一次，
      // 观感上就是全屏闪断一下。退全屏交给外壳在真正离开阅读器路由时做。
      if (!retainDesktopFullscreen) {
        await _setDesktopFullscreen(false);
      }
      return;
    }
    if (supportsOrientationLock) {
      await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> _setDesktopFullscreen(bool enabled) async {
    if (_isRunningInTest) {
      return;
    }
    if (await windowManager.isFullScreen() == enabled) {
      return;
    }
    await windowManager.setFullScreen(enabled);
  }
}
