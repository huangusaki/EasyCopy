// ignore_for_file: use_key_in_widget_constructors

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reader/app_screen/models.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/theme/app_theme.dart';
import 'package:reader/widgets/cover_image.dart';
import 'package:reader/widgets/settings_ui.dart';

part 'widgets/detail_cards.dart';
part 'widgets/detail_filters.dart';
part 'widgets/pager_widgets.dart';
part 'widgets/rank_widgets.dart';

class SurfaceBlock extends StatelessWidget {
  const SurfaceBlock({
    this.title,
    required this.child,
    this.actionLabel,
    this.onActionTap,
  });

  final String? title;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onActionTap;

  @override
  Widget build(BuildContext context) {
    return AppSurfaceCard(
      title: title,
      action: actionLabel != null && onActionTap != null
          ? TextButton(onPressed: onActionTap, child: Text(actionLabel!))
          : null,
      child: child,
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.actionLabel,
    this.onActionTap,
    this.padding = const EdgeInsets.only(bottom: 12),
    super.key,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onActionTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 4,
            height: 18,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: colorScheme.secondary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: colorScheme.onSurface,
                letterSpacing: 0.2,
              ),
            ),
          ),
          if (actionLabel != null && onActionTap != null)
            InkWell(
              onTap: onActionTap,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      actionLabel!,
                      style: TextStyle(
                        color: colorScheme.onSurface.withValues(alpha: 0.62),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: colorScheme.onSurface.withValues(alpha: 0.62),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
