import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

const String defaultDesktopUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

typedef HostNowProvider = DateTime Function();
typedef HostDirectoryProvider = Future<Directory> Function();
typedef HostProbeRunner = Future<HostProbeRecord> Function(String host);

class HostProbeRecord {
  const HostProbeRecord({
    required this.host,
    required this.success,
    required this.latencyMs,
    this.statusCode,
  });

  factory HostProbeRecord.fromJson(Map<String, Object?> json) {
    return HostProbeRecord(
      host: (json['host'] as String?) ?? '',
      success: (json['success'] as bool?) ?? false,
      latencyMs: (json['latencyMs'] as num?)?.toInt() ?? 999999,
      statusCode: (json['statusCode'] as num?)?.toInt(),
    );
  }

  final String host;
  final bool success;
  final int latencyMs;
  final int? statusCode;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'host': host,
      'success': success,
      'latencyMs': latencyMs,
      'statusCode': statusCode,
    };
  }
}

class HostProbeSnapshot {
  HostProbeSnapshot({
    required this.selectedHost,
    required this.checkedAt,
    required this.probes,
    this.sessionPinnedHost,
  });

  factory HostProbeSnapshot.fromJson(Map<String, Object?> json) {
    return HostProbeSnapshot(
      selectedHost: (json['selectedHost'] as String?) ?? '',
      checkedAt:
          DateTime.tryParse((json['checkedAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      probes: ((json['probes'] as List<Object?>?) ?? const <Object?>[])
          .whereType<Map>()
          .map(
            (Map<Object?, Object?> value) => HostProbeRecord.fromJson(
              value.map(
                (Object? key, Object? value) => MapEntry(key.toString(), value),
              ),
            ),
          )
          .toList(growable: false),
      sessionPinnedHost: json['sessionPinnedHost'] as String?,
    );
  }

  final String selectedHost;
  final DateTime checkedAt;
  final List<HostProbeRecord> probes;
  final String? sessionPinnedHost;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'selectedHost': selectedHost,
      'checkedAt': checkedAt.toIso8601String(),
      'sessionPinnedHost': sessionPinnedHost,
      'probes': probes.map((HostProbeRecord probe) => probe.toJson()).toList(),
    };
  }
}

class HostManager {
  HostManager({
    http.Client? client,
    List<String>? candidateHosts,
    HostDirectoryProvider? directoryProvider,
    HostNowProvider? now,
    HostProbeRunner? probeRunner,
    String userAgent = defaultDesktopUserAgent,
  }) : _client = client ?? http.Client(),
       _candidateHosts = (candidateHosts ?? _defaultCandidateHosts)
           .map(_normalizeHost)
           .toSet()
           .toList(growable: false),
       _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _now = now ?? DateTime.now,
       _probeRunner = probeRunner,
       _userAgent = userAgent,
       _currentHost = _normalizeHost(
         (candidateHosts ?? _defaultCandidateHosts).first,
       );

  static final HostManager instance = HostManager();

  static const Duration probeCacheTtl = Duration(hours: 12);
  static const Duration probeTimeout = Duration(seconds: 3);

  static const List<String> _defaultCandidateHosts = <String>[
    'www.2026copy.com',
    '2026copy.com',
    'www.2025copy.com',
    '2025copy.com',
    'www.copy20.com',
    'copy20.com',
    'www.copy-manga.com',
    'copy-manga.com',
    'www.copymanga.tv',
    'copymanga.tv',
    'www.mangacopy.com',
    'mangacopy.com',
    'www.copy2000.site',
    'copy2000.site',
  ];

  final http.Client _client;
  final List<String> _candidateHosts;
  final HostDirectoryProvider _directoryProvider;
  final HostNowProvider _now;
  final HostProbeRunner? _probeRunner;
  final String _userAgent;

  Future<void>? _initialization;
  HostProbeSnapshot? _snapshot;
  String _currentHost;
  String? _sessionPinnedHost;

  List<String> get candidateHosts => List<String>.unmodifiable(_candidateHosts);

  Set<String> get allowedHosts => _candidateHosts.toSet();

  String get currentHost => _sessionPinnedHost ?? _currentHost;

  Uri get baseUri => Uri.parse('https://$currentHost/');

  HostProbeSnapshot? get probeSnapshot => _snapshot;

  String? get sessionPinnedHost => _sessionPinnedHost;

  @visibleForTesting
  HostProbeSnapshot? get snapshot => _snapshot;

  Future<void> ensureInitialized() {
    return _initialization ??= _initialize();
  }

  Future<void> refreshProbes({bool force = false}) async {
    if (_initialization == null) {
      await ensureInitialized();
    }
    if (!force &&
        _snapshot != null &&
        _now().difference(_snapshot!.checkedAt) < probeCacheTtl) {
      return;
    }
    final List<HostProbeRecord> probes = await Future.wait(
      _candidateHosts.map(_probeHost),
    );
    final List<HostProbeRecord> ranked = _sortProbes(probes);
    final String nextHost = ranked
        .firstWhere(
          (HostProbeRecord probe) => probe.success,
          orElse: () =>
              HostProbeRecord(host: currentHost, success: true, latencyMs: 0),
        )
        .host;
    _currentHost = nextHost;
    _snapshot = HostProbeSnapshot(
      selectedHost: nextHost,
      checkedAt: _now(),
      probes: ranked,
      sessionPinnedHost: _sessionPinnedHost,
    );
    await _saveSnapshot();
  }

  Future<void> pinSessionHost(String host) async {
    await ensureInitialized();
    final String normalizedHost = _normalizeHost(host);
    if (!_candidateHosts.contains(normalizedHost)) {
      return;
    }
    _sessionPinnedHost = normalizedHost;
    _currentHost = normalizedHost;
    await _persistCurrentState();
  }

  Future<void> clearSessionPin() async {
    await ensureInitialized();
    _sessionPinnedHost = null;
    await _persistCurrentState();
  }

  Future<String> failover({Iterable<String> exclude = const <String>[]}) async {
    await refreshProbes(force: true);
    final Set<String> excludedHosts = exclude.map(_normalizeHost).toSet()
      ..add(_normalizeHost(currentHost));
    final List<HostProbeRecord> ranked = _sortProbes(_snapshot?.probes ?? []);
    final HostProbeRecord? nextHost = ranked
        .cast<HostProbeRecord?>()
        .firstWhere((HostProbeRecord? probe) {
          return probe != null &&
              probe.success &&
              !excludedHosts.contains(_normalizeHost(probe.host));
        }, orElse: () => null);
    if (nextHost == null) {
      return currentHost;
    }
    _currentHost = nextHost.host;
    if (_sessionPinnedHost != null) {
      _sessionPinnedHost = nextHost.host;
    }
    await _persistCurrentState();
    return currentHost;
  }

  Uri resolvePath(String path) {
    final String normalizedPath = path.startsWith('/')
        ? path.substring(1)
        : path;
    return baseUri.resolve(normalizedPath);
  }

  Uri resolveNavigationUri(String href, {Uri? currentUri}) {
    final String trimmedHref = href.trim();
    if (trimmedHref.isEmpty) {
      return rewriteToCurrentHost(currentUri ?? baseUri);
    }

    final Uri? parsed = Uri.tryParse(trimmedHref);
    if (parsed != null && parsed.hasScheme) {
      return rewriteToCurrentHost(parsed);
    }

    return rewriteToCurrentHost((currentUri ?? baseUri).resolve(trimmedHref));
  }

  Uri rewriteToCurrentHost(Uri uri) {
    if (!uri.hasScheme) {
      return uri;
    }
    if (!allowedHosts.contains(uri.host.toLowerCase())) {
      return uri;
    }
    return uri.replace(
      scheme: baseUri.scheme,
      host: currentHost,
      port: baseUri.hasPort ? baseUri.port : null,
    );
  }

  bool isAllowedNavigationUri(Uri? uri) {
    if (uri == null || !uri.hasScheme) {
      return true;
    }
    if (uri.scheme == 'about' || uri.scheme == 'data') {
      return true;
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return false;
    }
    return allowedHosts.contains(uri.host.toLowerCase());
  }

  Future<void> _initialize() async {
    _snapshot = await _loadSnapshot();
    if (_snapshot != null) {
      _currentHost = _snapshot!.selectedHost.isEmpty
          ? _currentHost
          : _normalizeHost(_snapshot!.selectedHost);
      _sessionPinnedHost = _snapshot!.sessionPinnedHost == null
          ? null
          : _normalizeHost(_snapshot!.sessionPinnedHost!);
    }
    if (_snapshot == null ||
        _now().difference(_snapshot!.checkedAt) >= probeCacheTtl) {
      await refreshProbes(force: true);
    }
  }

  Future<HostProbeRecord> _probeHost(String host) async {
    if (_probeRunner != null) {
      return _probeRunner(host);
    }
    final Stopwatch stopwatch = Stopwatch()..start();
    try {
      final http.Response response = await _client
          .get(
            Uri.parse('https://$host/'),
            headers: <String, String>{'User-Agent': _userAgent},
          )
          .timeout(probeTimeout);
      stopwatch.stop();
      final bool isCompatible = _looksLikeSupportedHome(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      return HostProbeRecord(
        host: host,
        success: response.statusCode < 500 && isCompatible,
        latencyMs: stopwatch.elapsedMilliseconds,
        statusCode: response.statusCode,
      );
    } catch (_) {
      stopwatch.stop();
      return HostProbeRecord(host: host, success: false, latencyMs: 999999);
    }
  }

  List<HostProbeRecord> _sortProbes(List<HostProbeRecord> probes) {
    final List<HostProbeRecord> ranked = probes.toList(growable: false);
    ranked.sort((HostProbeRecord left, HostProbeRecord right) {
      if (left.success != right.success) {
        return left.success ? -1 : 1;
      }
      return left.latencyMs.compareTo(right.latencyMs);
    });
    return ranked;
  }

  Future<File> _snapshotFile() async {
    final Directory directory = await _directoryProvider();
    return File('${directory.path}${Platform.pathSeparator}host_probe.json');
  }

  Future<HostProbeSnapshot?> _loadSnapshot() async {
    try {
      final File file = await _snapshotFile();
      if (!await file.exists()) {
        return null;
      }
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return null;
      }
      return HostProbeSnapshot.fromJson(
        decoded.map(
          (Object? key, Object? value) => MapEntry(key.toString(), value),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistCurrentState() async {
    _snapshot = HostProbeSnapshot(
      selectedHost: _currentHost,
      checkedAt: _snapshot?.checkedAt ?? _now(),
      probes: _snapshot?.probes ?? const <HostProbeRecord>[],
      sessionPinnedHost: _sessionPinnedHost,
    );
    await _saveSnapshot();
  }

  Future<void> _saveSnapshot() async {
    try {
      final File file = await _snapshotFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(_snapshot?.toJson() ?? {}),
      );
    } catch (_) {
      // Best-effort persistence only.
    }
  }

  static String _normalizeHost(String host) {
    return host.trim().toLowerCase();
  }

  static bool _looksLikeSupportedHome(String body) {
    final String normalized = body.toLowerCase();
    return normalized.contains('content-box') &&
        normalized.contains('swiperlist') &&
        normalized.contains('comicrank');
  }
}
