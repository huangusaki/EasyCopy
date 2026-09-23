import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:reader/widgets/desktop/desktop_dock.dart';
import 'package:reader/widgets/mobile_floating_nav_bar.dart';

/// 不读取 Scaffold.extendBody 注入的 padding，按真实遮挡计算一次避让。
class StandardBottomInset extends StatelessWidget {
  const StandardBottomInset({
    required this.isDesktop,
    required this.navigationVisible,
    required this.systemBottomInset,
    required this.keyboardVisible,
    super.key,
  });

  final bool isDesktop;
  final ValueListenable<bool> navigationVisible;
  final double systemBottomInset;
  final bool keyboardVisible;

  @override
  Widget build(BuildContext context) {
    const double contentGap = 8;
    if (isDesktop) {
      return const SizedBox(
        height: DesktopDock.bottomOverlayExtent + contentGap,
      );
    }
    final double systemBottom = keyboardVisible ? 0 : systemBottomInset;
    return ValueListenableBuilder<bool>(
      valueListenable: navigationVisible,
      builder: (BuildContext context, bool visible, Widget? child) {
        final double inset = visible && !keyboardVisible
            ? MobileFloatingNavBar.bottomOverlayExtent(systemBottom)
            : systemBottom;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: visible ? Curves.easeOutCubic : Curves.easeInCubic,
          height: inset + contentGap,
        );
      },
    );
  }
}
