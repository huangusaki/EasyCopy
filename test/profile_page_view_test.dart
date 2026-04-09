import 'package:easy_copy/models/page_models.dart';
import 'package:easy_copy/theme/app_theme.dart';
import 'package:easy_copy/widgets/profile_page_view.dart';
import 'package:easy_copy/services/host_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('host settings page shows failed hosts and disables switching them', (
    WidgetTester tester,
  ) async {
    int selectedCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.buildLightTheme(),
        home: Scaffold(
          body: ProfilePageView(
            page: ProfilePageData.loggedOut(uri: 'https://mangacopy.com/profile'),
            onAuthenticate: () {},
            onLogout: () {},
            onOpenComic: (_) {},
            onOpenHistory: (_) {},
            onOpenCollections: () {},
            onOpenHistoryPage: () {},
            onOpenCachedComicPage: () {},
            currentHost: 'mangacopy.com',
            knownHosts: const <String>[
              'www.2026copy.com',
              '2026copy.com',
              'copy20.com',
              'mangacopy.com',
            ],
            candidateHosts: const <String>['copy20.com'],
            candidateHostAliases: const <String, List<String>>{
              'copy20.com': <String>[],
            },
            hostSnapshot: HostProbeSnapshot(
              selectedHost: 'mangacopy.com',
              checkedAt: DateTime(2026, 4, 9, 18, 30),
              probes: const <HostProbeRecord>[
                HostProbeRecord(
                  host: 'copy20.com',
                  success: true,
                  latencyMs: 38,
                  statusCode: 200,
                ),
                HostProbeRecord(
                  host: 'mangacopy.com',
                  success: true,
                  latencyMs: 72,
                  statusCode: 200,
                ),
                HostProbeRecord(
                  host: 'www.2026copy.com',
                  success: false,
                  latencyMs: 999999,
                ),
                HostProbeRecord(
                  host: '2026copy.com',
                  success: false,
                  latencyMs: 999999,
                ),
              ],
            ),
            onRefreshHosts: () async {},
            onUseAutomaticHostSelection: () async {},
            onSelectHost: (String value) async {
              selectedCount += 1;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('管理域名'));
    await tester.pumpAndSettle();

    expect(find.text('www.2026copy.com'), findsOneWidget);
    expect(find.text('2026copy.com'), findsOneWidget);
    expect(find.text('连接失败'), findsNWidgets(2));

    await tester.tap(find.text('www.2026copy.com'));
    await tester.pumpAndSettle();
    expect(selectedCount, 0);

    await tester.tap(find.text('copy20.com'));
    await tester.pumpAndSettle();
    expect(selectedCount, 1);
  });
}
