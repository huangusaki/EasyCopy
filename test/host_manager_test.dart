import 'dart:io';

import 'package:easy_copy/services/host_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('host manager ranks probes, rewrites hosts, and supports failover', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'easy_copy_hosts',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final DateTime fixedNow = DateTime(2026, 3, 6, 12);
    final HostManager manager = HostManager(
      candidateHosts: const <String>[
        'slow.example',
        'fast.example',
        'down.example',
      ],
      directoryProvider: () async => tempDir,
      now: () => fixedNow,
      probeRunner: (String host) async {
        switch (host) {
          case 'fast.example':
            return const HostProbeRecord(
              host: 'fast.example',
              success: true,
              latencyMs: 40,
              statusCode: 200,
            );
          case 'slow.example':
            return const HostProbeRecord(
              host: 'slow.example',
              success: true,
              latencyMs: 90,
              statusCode: 200,
            );
          default:
            return const HostProbeRecord(
              host: 'down.example',
              success: false,
              latencyMs: 999999,
            );
        }
      },
    );

    await manager.ensureInitialized();

    expect(manager.currentHost, 'fast.example');
    expect(
      manager.resolvePath('/rank').toString(),
      'https://fast.example/rank',
    );
    expect(
      manager.rewriteToCurrentHost(Uri.parse('https://slow.example/comics')).host,
      'fast.example',
    );

    await manager.pinSessionHost('slow.example');
    expect(manager.currentHost, 'slow.example');

    final String failoverHost = await manager.failover(
      exclude: const <String>['slow.example'],
    );
    expect(failoverHost, 'fast.example');
    expect(manager.currentHost, 'fast.example');
  });

  test('host manager reuses persisted probe results within cache ttl', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'easy_copy_hosts_cache',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    int probeCalls = 0;
    final HostManager first = HostManager(
      candidateHosts: const <String>['alpha.example', 'beta.example'],
      directoryProvider: () async => tempDir,
      now: () => DateTime(2026, 3, 6, 12),
      probeRunner: (String host) async {
        probeCalls += 1;
        return HostProbeRecord(
          host: host,
          success: true,
          latencyMs: host == 'alpha.example' ? 20 : 80,
          statusCode: 200,
        );
      },
    );

    await first.ensureInitialized();
    expect(first.currentHost, 'alpha.example');
    expect(probeCalls, 2);

    final HostManager second = HostManager(
      candidateHosts: const <String>['alpha.example', 'beta.example'],
      directoryProvider: () async => tempDir,
      now: () => DateTime(2026, 3, 6, 13),
      probeRunner: (String host) async {
        probeCalls += 1;
        return HostProbeRecord(
          host: host,
          success: true,
          latencyMs: host == 'alpha.example' ? 999 : 1,
          statusCode: 200,
        );
      },
    );

    await second.ensureInitialized();

    expect(second.currentHost, 'alpha.example');
    expect(probeCalls, 2);
  });

  test('host manager rejects incompatible landing pages during probing', () async {
    final Directory tempDir = await Directory.systemTemp.createTemp(
      'easy_copy_hosts_probe',
    );
    addTearDown(() => tempDir.delete(recursive: true));

    final HostManager manager = HostManager(
      client: MockClient((http.Request request) async {
        if (request.url.host == 'good.example') {
          return http.Response(
            '<main class="content-box"><div class="swiperList"></div><div class="comicRank"></div></main>',
            200,
          );
        }
        return http.Response('<html><body><div id="lander"></div></body></html>', 200);
      }),
      candidateHosts: const <String>['bad.example', 'good.example'],
      directoryProvider: () async => tempDir,
      now: () => DateTime(2026, 3, 7, 1),
    );

    await manager.ensureInitialized();

    expect(manager.currentHost, 'good.example');
    expect(manager.snapshot?.probes.first.success, isTrue);
    expect(
      manager.snapshot?.probes.any(
        (HostProbeRecord probe) => probe.host == 'bad.example' && !probe.success,
      ),
      isTrue,
    );
  });
}
