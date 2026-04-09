import 'dart:io';

import 'package:easy_copy/services/host_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HostManager', () {
    late Directory tempDirectory;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp('easy_copy_host_');
    });

    tearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('refreshProbes persists failed hosts while keeping candidates selectable', () async {
      final DateTime now = DateTime(2026, 4, 9, 18, 0);
      final HostManager manager = HostManager(
        candidateHosts: const <String>[
          'www.2026copy.com',
          '2026copy.com',
          'mangacopy.com',
          'dead.example',
        ],
        directoryProvider: () async => tempDirectory,
        now: () => now,
        connectivityRunner: (String host) async => host != 'dead.example',
        probeRunner: (String host) async {
          switch (host) {
            case 'www.2026copy.com':
              return const HostProbeRecord(
                host: 'www.2026copy.com',
                success: true,
                latencyMs: 80,
                statusCode: 200,
                addressSignature: '1.1.1.1',
              );
            case '2026copy.com':
              return const HostProbeRecord(
                host: '2026copy.com',
                success: true,
                latencyMs: 90,
                statusCode: 200,
                addressSignature: '1.1.1.1',
              );
            case 'mangacopy.com':
              return const HostProbeRecord(
                host: 'mangacopy.com',
                success: true,
                latencyMs: 50,
                statusCode: 200,
                addressSignature: '2.2.2.2',
              );
            default:
              fail('Unexpected probe host: $host');
          }
        },
      );

      await manager.refreshProbes(force: true);

      expect(
        manager.knownHosts,
        const <String>[
          'www.2026copy.com',
          '2026copy.com',
          'mangacopy.com',
          'dead.example',
        ],
      );
      expect(
        manager.candidateHosts,
        const <String>['mangacopy.com', 'www.2026copy.com'],
      );
      expect(
        manager.candidateHostAliases,
        const <String, List<String>>{
          'mangacopy.com': <String>[],
          'www.2026copy.com': <String>['2026copy.com'],
        },
      );

      final HostProbeSnapshot? snapshot = manager.probeSnapshot;
      expect(snapshot, isNotNull);
      expect(snapshot!.selectedHost, 'mangacopy.com');
      expect(
        snapshot.probes.map((HostProbeRecord probe) => probe.host).toList(),
        const <String>[
          'mangacopy.com',
          'www.2026copy.com',
          '2026copy.com',
          'dead.example',
        ],
      );

      final HostProbeRecord failedProbe = snapshot.probes.firstWhere(
        (HostProbeRecord probe) => probe.host == 'dead.example',
      );
      expect(failedProbe.success, isFalse);
      expect(failedProbe.statusCode, isNull);
      expect(failedProbe.latencyMs, 999999);
    });
  });
}
