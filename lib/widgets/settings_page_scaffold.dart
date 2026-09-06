import 'package:flutter/material.dart';
import 'package:reader/widgets/responsive_layout.dart';

/// Settings routes keep an opaque background even when the app uses wallpaper.
class SettingsPageScaffold extends StatelessWidget {
  const SettingsPageScaffold({
    required this.title,
    required this.body,
    this.actions,
    super.key,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: opaquePageBackground(context),
      appBar: AppBar(title: Text(title), actions: actions),
      body: body,
    );
  }
}
