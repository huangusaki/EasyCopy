import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

void perfLog(String message) {
  if (!kReleaseMode) {
    debugPrint('[perf]$message');
  }
}

class FrameJankLogger {
  FrameJankLogger._();

  static bool _installed = false;

  static void install() {
    if (_installed || kReleaseMode) {
      return;
    }
    _installed = true;
    SchedulerBinding.instance.addTimingsCallback((List<FrameTiming> timings) {
      for (final FrameTiming timing in timings) {
        final int totalMs = timing.totalSpan.inMilliseconds;
        if (totalMs < 20) {
          continue;
        }
        perfLog(
          '[jank] total=${totalMs}ms '
          'build=${timing.buildDuration.inMilliseconds}ms '
          'raster=${timing.rasterDuration.inMilliseconds}ms '
          'vsyncOverhead=${timing.vsyncOverhead.inMilliseconds}ms',
        );
      }
    });
  }
}
