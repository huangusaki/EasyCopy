import 'package:flutter/material.dart';
import 'package:reader/models/app_preferences.dart';

const double kWideLayoutBreakpoint = 900;
const double kWideReaderControlsMaxWidth = 720;

double wideContentMaxWidth(double viewportWidth) {
  return (viewportWidth * 0.86).clamp(kWideLayoutBreakpoint, 1760.0);
}

bool usesWideLayout(BuildContext context) {
  return MediaQuery.sizeOf(context).width >= kWideLayoutBreakpoint;
}

bool usesDesktopWindowShell(BuildContext context) {
  final TargetPlatform platform = Theme.of(context).platform;
  final bool isDesktopPlatform = switch (platform) {
    TargetPlatform.windows ||
    TargetPlatform.macOS ||
    TargetPlatform.linux => true,
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.fuchsia => false,
  };
  return isDesktopPlatform && usesWideLayout(context);
}

EdgeInsets standardContentPadding(BuildContext context) {
  if (!usesWideLayout(context)) {
    return const EdgeInsets.symmetric(horizontal: 16);
  }
  final double viewportWidth = MediaQuery.sizeOf(context).width;
  final double maxContentWidth = wideContentMaxWidth(viewportWidth);
  if (viewportWidth > maxContentWidth) {
    return EdgeInsets.symmetric(
      horizontal: (viewportWidth - maxContentWidth) / 2 + 16,
    );
  }
  return const EdgeInsets.symmetric(horizontal: 32);
}

int responsiveComicCrossAxisCount(
  BuildContext context,
  double availableWidth, {
  double minItemWidth = 165,
  double spacing = 12,
  int mobileCount = 3,
  int maxCount = 6,
}) {
  if (!usesWideLayout(context)) {
    return mobileCount;
  }
  if (!availableWidth.isFinite || availableWidth <= 0) {
    return mobileCount;
  }

  final int count = ((availableWidth + spacing) / (minItemWidth + spacing))
      .floor()
      .clamp(mobileCount, maxCount)
      .toInt();
  return count;
}

double wideReaderMaxWidth(BuildContext context, ReaderPageFit fit) {
  if (!usesWideLayout(context) || fit != ReaderPageFit.fitWidth) {
    return double.infinity;
  }
  final double screenWidth = MediaQuery.sizeOf(context).width;
  return screenWidth >= 1280 ? 1100 : 980;
}

Color opaquePageBackground(BuildContext context) {
  final ThemeData theme = Theme.of(context);
  final Color base = theme.scaffoldBackgroundColor;
  return base.a == 0 ? theme.colorScheme.surface : base;
}
