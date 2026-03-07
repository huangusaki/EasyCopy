import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

  bool get isAndroidSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

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
}
