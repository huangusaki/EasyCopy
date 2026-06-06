import 'package:easy_copy/easy_copy_screen/widgets.dart';
import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pure black navigation indicator uses a dark container color', () {
    final ThemeData theme = AppTheme.buildPureBlackTheme();

    expect(
      theme.navigationBarTheme.indicatorColor,
      theme.colorScheme.secondaryContainer.withValues(alpha: 0.78),
    );
    expect(
      theme.navigationBarTheme.indicatorColor!.computeLuminance(),
      lessThan(0.03),
    );
  });

  testWidgets('active rank filter chip stays dark in pure black theme', (
    WidgetTester tester,
  ) async {
    final ThemeData theme = AppTheme.buildPureBlackTheme();

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Material(
          child: Center(
            child: LinkChip(label: '日排行', active: true, onTap: () {}),
          ),
        ),
      ),
    );

    final AnimatedContainer chip = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final BoxDecoration decoration = chip.decoration! as BoxDecoration;
    final Text label = tester.widget<Text>(find.text('日排行'));

    expect(decoration.color, theme.colorScheme.secondaryContainer);
    expect(
      decoration.border!.top.color,
      theme.colorScheme.outline.withValues(alpha: 0.82),
    );
    expect(label.style!.color, theme.colorScheme.onSecondaryContainer);
  });

  testWidgets('rank badge stays dark in pure black theme', (
    WidgetTester tester,
  ) async {
    final ThemeData theme = AppTheme.buildPureBlackTheme();

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Material(
          child: RankCard(
            item: const RankEntryData(
              rankLabel: '1',
              title: '榜单条目',
              coverUrl: '',
              href: '/comic/1',
              heat: '1000',
              trend: 'up',
            ),
            onTap: () {},
          ),
        ),
      ),
    );

    final Container badge = tester.widget<Container>(
      find.ancestor(of: find.text('1'), matching: find.byType(Container)).first,
    );
    final BoxDecoration decoration = badge.decoration! as BoxDecoration;
    final Text label = tester.widget<Text>(find.text('1'));

    expect(decoration.color, theme.colorScheme.secondaryContainer);
    expect(label.style!.color, theme.colorScheme.onSecondaryContainer);
  });
}
