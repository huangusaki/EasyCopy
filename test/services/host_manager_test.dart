import 'dart:convert';
import 'dart:io';

import 'package:easy_copy/services/host_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HostManager', () {
    late Directory tempDirectory;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp(
        'copy_fullter_host_manager_test_',
      );
    });

    tearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('ignores legacy pinned host snapshot without pin mode', () async {
      final File snapshotFile = File(
        '${tempDirectory.path}${Platform.pathSeparator}host_probe.json',
      );
      await snapshotFile.writeAsString(
        jsonEncode(<String, Object?>{
          'selectedHost': 'b.example.com',
          'checkedAt': DateTime(2026, 4, 1).toIso8601String(),
          'sessionPinnedHost': 'a.example.com',
          'probes': <Map<String, Object?>>[
            <String, Object?>{
              'host': 'b.example.com',
              'success': true,
              'latencyMs': 20,
            },
          ],
        }),
      );

      final HostManager manager = HostManager(
        candidateHosts: const <String>['a.example.com', 'b.example.com'],
        directoryProvider: () async => tempDirectory,
        probeRunner: (String host) async => HostProbeRecord(
          host: host,
          success: true,
          latencyMs: host == 'b.example.com' ? 10 : 30,
        ),
      );

      await manager.ensureInitialized();

      expect(manager.sessionPinnedHost, isNull);
      expect(manager.currentHost, 'b.example.com');
    });

    test('restores manual pin saved by current version', () async {
      final HostManager firstManager = HostManager(
        candidateHosts: const <String>['a.example.com', 'b.example.com'],
        directoryProvider: () async => tempDirectory,
        probeRunner: (String host) async => HostProbeRecord(
          host: host,
          success: true,
          latencyMs: host == 'b.example.com' ? 10 : 30,
        ),
      );
      await firstManager.ensureInitialized();
      await firstManager.pinSessionHost('a.example.com');

      final HostManager secondManager = HostManager(
        candidateHosts: const <String>['a.example.com', 'b.example.com'],
        directoryProvider: () async => tempDirectory,
        probeRunner: (String host) async => HostProbeRecord(
          host: host,
          success: true,
          latencyMs: host == 'b.example.com' ? 10 : 30,
        ),
      );

      await secondManager.ensureInitialized();

      expect(secondManager.sessionPinnedHost, 'a.example.com');
      expect(secondManager.currentHost, 'a.example.com');
    });
  });
}
