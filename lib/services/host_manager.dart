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
typedef HostConnectivityRunner = Future<bool> Function(String host);
typedef HostAddressLookup = Future<List<String>> Function(String host);

class HostProbeRecord {
  const HostProbeRecord({
    required this.host,
    required this.success,
    required this.latencyMs,
    this.statusCode,
    this.addressSignature,
  });

  factory HostProbeRecord.fromJson(Map<String, Object?> json) {
    return HostProbeRecord(
      host: (json['host'] as String?) ?? '',
      success: (json['success'] as bool?) ?? false,
      latencyMs: (json['latencyMs'] as num?)?.toInt() ?? 999999,
      statusCode: (json['statusCode'] as num?)?.toInt(),
      addressSignature: (json['addressSignature'] as String?)?.trim(),
    );
  }

  final String host;
  final bool success;
  final int latencyMs;
  final int? statusCode;
  final String? addressSignature;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'host': host,
      'success': success,
      'latencyMs': latencyMs,
      'statusCode': statusCode,
      'addressSignature': addressSignature,
    };
  }
}

class _HostAliasGroup {
  const _HostAliasGroup({
    required this.primaryHost,
    required this.aliases,
    required this.bestLatencyMs,
    required this.preferenceIndex,
  });

  final String primaryHost;
  final List<String> aliases;
  final int bestLatencyMs;
  final int preferenceIndex;
}

class HostProbeSnapshot {
  HostProbeSnapshot({
    required this.selectedHost,
    required this.checkedAt,
    required this.probes,
    this.sessionPinnedHost,
  });

  factory HostProbeSnapshot.fromJson(Map<String, Object?> json) {
    final String pinMode = (json['pinMode'] as String?)?.trim() ?? '';
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
      sessionPinnedHost: pinMode == 'manual'
          ? json['sessionPinnedHost'] as String?
          : null,
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
      'pinMode': sessionPinnedHost == null ? '' : 'manual',
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
    HostConnectivityRunner? connectivityRunner,
    HostAddressLookup? addressLookup,
    String userAgent = defaultDesktopUserAgent,
  }) : _client = client ?? http.Client(),
       _seedHosts = _normalizeHosts(
         candidateHosts ?? _buildDefaultCandidateHosts(),
       ),
       _candidateHosts = const <String>[],
       _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _now = now ?? DateTime.now,
       _probeRunner = probeRunner,
       _connectivityRunner = connectivityRunner,
       _addressLookup = addressLookup,
       _userAgent = userAgent,
       _currentHost = _firstHost(
         candidateHosts ?? _buildDefaultCandidateHosts(),
       );

  static final HostManager instance = HostManager();

  static const Duration probeCacheTtl = Duration(hours: 12);
  static const Duration probeTimeout = Duration(seconds: 3);
  static const Duration connectTimeout = Duration(seconds: 2);

  final http.Client _client;
  final List<String> _seedHosts;
  List<String> _candidateHosts;
  final HostDirectoryProvider _directoryProvider;
  final HostNowProvider _now;
  final HostProbeRunner? _probeRunner;
  final HostConnectivityRunner? _connectivityRunner;
  final HostAddressLookup? _addressLookup;
  final String _userAgent;

  Future<void>? _initialization;
  Future<void>? _probeRefresh;
  HostProbeSnapshot? _snapshot;
  String _currentHost;
  String? _sessionPinnedHost;
  Map<String, List<String>> _candidateHostAliases =
      const <String, List<String>>{};
  final Map<String, String> _addressSignatureCache = <String, String>{};

  List<String> get candidateHosts => List<String>.unmodifiable(_candidateHosts);

  List<String> get knownHosts => List<String>.unmodifiable(
    _mergeHosts(<String>[
      ..._seedHosts,
      _currentHost,
      if (_sessionPinnedHost != null) _sessionPinnedHost!,
      if ((_snapshot?.selectedHost ?? '').trim().isNotEmpty)
        _snapshot!.selectedHost,
      for (final HostProbeRecord probe
          in _snapshot?.probes ?? const <HostProbeRecord>[])
        probe.host,
    ]),
  );

  Map<String, List<String>> get candidateHostAliases =>
      Map<String, List<String>>.unmodifiable(
        _candidateHostAliases.map(
          (String host, List<String> aliases) =>
              MapEntry(host, List<String>.unmodifiable(aliases)),
        ),
      );

  Set<String> get allowedHosts => <String>{
    ..._seedHosts,
    ..._candidateHosts,
    if (_currentHost.isNotEmpty) _currentHost,
    if ((_sessionPinnedHost ?? '').trim().isNotEmpty)
      _normalizeHost(_sessionPinnedHost!),
    if ((_snapshot?.selectedHost ?? '').trim().isNotEmpty)
      _normalizeHost(_snapshot!.selectedHost),
    for (final HostProbeRecord probe
        in _snapshot?.probes ?? const <HostProbeRecord>[])
      if (_normalizeHost(probe.host).isNotEmpty) _normalizeHost(probe.host),
  };

  String get currentHost => _sessionPinnedHost ?? _currentHost;

  Uri get baseUri => Uri.parse('https://$currentHost/');

  HostProbeSnapshot? get probeSnapshot => _snapshot;

  String? get sessionPinnedHost => _sessionPinnedHost;

  @visibleForTesting
  HostProbeSnapshot? get snapshot => _snapshot;

  Future<void> ensureInitialized() {
    return _initialization ??= _initialize();
  }

  Future<void> refreshProbes({bool force = false}) {
    final Future<void>? activeRefresh = _probeRefresh;
    if (activeRefresh != null) {
      return activeRefresh;
    }
    final Future<void> refresh = _refreshProbes(force: force);
    _probeRefresh = refresh;
    return refresh.whenComplete(() {
      if (identical(_probeRefresh, refresh)) {
        _probeRefresh = null;
      }
    });
  }

  Future<void> _refreshProbes({required bool force}) async {
    if (_initialization == null) {
      await ensureInitialized();
    }
    if (!force &&
        _snapshot != null &&
        _now().difference(_snapshot!.checkedAt) < probeCacheTtl) {
      _candidateHosts = _successfulProbeHosts(_snapshot!.probes);
      _candidateHostAliases = _buildCandidateHostAliases(_snapshot!.probes);
      return;
    }
    final List<String> hostsToProbe = knownHosts;
    final List<HostProbeRecord> probes = hostsToProbe.isEmpty
        ? const <HostProbeRecord>[]
        : await Future.wait(hostsToProbe.map(_probeKnownHost));
    final List<HostProbeRecord> ranked = _sortProbes(probes);
    _candidateHosts = _successfulProbeHosts(ranked);
    _candidateHostAliases = _buildCandidateHostAliases(ranked);
    final String? pinnedHost = _sessionPinnedHost == null
        ? null
        : _normalizeHost(_sessionPinnedHost!);
    final bool pinnedIsAvailable =
        pinnedHost != null &&
        ranked.any(
          (HostProbeRecord probe) =>
              _normalizeHost(probe.host) == pinnedHost && probe.success,
        );
    if (pinnedHost != null && !pinnedIsAvailable) {
      _sessionPinnedHost = null;
    }
    final String nextHost = _selectAutomaticHost(ranked);
    if (nextHost.isNotEmpty) {
      _currentHost = nextHost;
    }
    _snapshot = HostProbeSnapshot(
      selectedHost: nextHost.isEmpty ? _currentHost : nextHost,
      checkedAt: _now(),
      probes: ranked,
      sessionPinnedHost: _sessionPinnedHost,
    );
    await _saveSnapshot();
  }

  Future<void> pinSessionHost(String host) async {
    await ensureInitialized();
    final String normalizedHost = _normalizeHost(host);
    if (normalizedHost.isEmpty) {
      throw StateError('域名不可用，请选择测速成功的域名。');
    }
    final HostProbeRecord? cachedProbe = _probeForHost(normalizedHost);
    final bool cacheFresh =
        _snapshot != null &&
        _now().difference(_snapshot!.checkedAt) < probeCacheTtl;
    final HostProbeRecord probe =
        cachedProbe != null && cachedProbe.success && cacheFresh
        ? cachedProbe
        : await _validateSelectableHost(normalizedHost);
    _sessionPinnedHost = normalizedHost;
    _currentHost = normalizedHost;
    _snapshot = HostProbeSnapshot(
      selectedHost: (_snapshot?.selectedHost ?? '').trim().isEmpty
          ? normalizedHost
          : _normalizeHost(_snapshot!.selectedHost),
      checkedAt: _now(),
      probes: _upsertProbe(
        probe,
        _snapshot?.probes ?? const <HostProbeRecord>[],
      ),
      sessionPinnedHost: _sessionPinnedHost,
    );
    _candidateHosts = _successfulProbeHosts(_snapshot!.probes);
    _candidateHostAliases = _buildCandidateHostAliases(_snapshot!.probes);
    await _saveSnapshot();
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
      _candidateHosts = _successfulProbeHosts(_snapshot!.probes);
      _candidateHostAliases = _buildCandidateHostAliases(_snapshot!.probes);
    }
    // Cold start should reuse the last known host immediately. Fresh probes run
    // later in the background so the first screen is not blocked on network.
  }

  Future<HostProbeRecord> _probeKnownHost(String host) async {
    final String normalizedHost = _normalizeHost(host);
    if (normalizedHost.isEmpty) {
      return const HostProbeRecord(
        host: '',
        success: false,
        latencyMs: 999999,
      );
    }
    final bool reachable = await _isHostReachable(normalizedHost);
    if (!reachable) {
      return HostProbeRecord(
        host: normalizedHost,
        success: false,
        latencyMs: 999999,
        addressSignature: _addressSignatureCache[normalizedHost],
      );
    }
    return _probeHost(normalizedHost);
  }

  Future<HostProbeRecord> _probeHost(String host) async {
    if (_probeRunner != null) {
      return _probeRunner(host);
    }
    final Stopwatch stopwatch = Stopwatch()..start();
    final String? addressSignature = await _resolveAddressSignature(host);
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
        addressSignature: addressSignature,
      );
    } catch (_) {
      stopwatch.stop();
      return HostProbeRecord(
        host: host,
        success: false,
        latencyMs: 999999,
        addressSignature: addressSignature,
      );
    }
  }

  Future<bool> _isHostReachable(String host) async {
    if (_connectivityRunner != null) {
      return _connectivityRunner(host);
    }
    final String normalizedHost = _normalizeHost(host);
    if (normalizedHost.isEmpty) {
      return false;
    }
    try {
      final List<String> addresses = await _lookupHostAddresses(normalizedHost);
      if (addresses.isEmpty) {
        return false;
      }
      final String? addressSignature = _signatureForAddresses(addresses);
      if (addressSignature != null) {
        _addressSignatureCache[normalizedHost] = addressSignature;
      }
    } catch (_) {
      return false;
    }
    Socket? socket;
    try {
      socket = await Socket.connect(
        normalizedHost,
        443,
        timeout: connectTimeout,
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  Future<HostProbeRecord> _validateSelectableHost(String host) async {
    final bool reachable = await _isHostReachable(host);
    if (!reachable) {
      throw StateError('域名不可用，请选择测速成功的域名。');
    }
    final HostProbeRecord probe = await _probeHost(host);
    if (!probe.success) {
      throw StateError('域名不可用，请选择测速成功的域名。');
    }
    return probe;
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

  List<String> _successfulProbeHosts(List<HostProbeRecord> probes) {
    return _buildHostAliasGroups(
      probes,
    ).map((_HostAliasGroup group) => group.primaryHost).toList(growable: false);
  }

  Map<String, List<String>> _buildCandidateHostAliases(
    List<HostProbeRecord> probes,
  ) {
    final Map<String, List<String>> aliases = <String, List<String>>{};
    for (final _HostAliasGroup group in _buildHostAliasGroups(probes)) {
      aliases[group.primaryHost] = List<String>.unmodifiable(group.aliases);
    }
    return aliases;
  }

  List<_HostAliasGroup> _buildHostAliasGroups(List<HostProbeRecord> probes) {
    final List<HostProbeRecord> successful = probes
        .where(
          (HostProbeRecord probe) =>
              probe.success && _normalizeHost(probe.host).isNotEmpty,
        )
        .toList(growable: false);
    if (successful.isEmpty) {
      return const <_HostAliasGroup>[];
    }
    final Set<String> successfulHosts = <String>{
      for (final HostProbeRecord probe in successful)
        _normalizeHost(probe.host),
    };
    final List<String> preferenceOrder = _mergeHosts(<String>[
      ..._seedHosts,
      if (_sessionPinnedHost != null) _sessionPinnedHost!,
      _currentHost,
      ..._candidateHosts,
      if ((_snapshot?.selectedHost ?? '').trim().isNotEmpty)
        _snapshot!.selectedHost,
      for (final HostProbeRecord probe
          in _snapshot?.probes ?? const <HostProbeRecord>[])
        probe.host,
      for (final HostProbeRecord probe in successful) probe.host,
    ]);
    final Map<String, int> preferenceIndex = <String, int>{
      for (int index = 0; index < preferenceOrder.length; index += 1)
        preferenceOrder[index]: index,
    };
    final Map<String, List<HostProbeRecord>> probesByGroup =
        <String, List<HostProbeRecord>>{};
    for (final HostProbeRecord probe in successful) {
      final String normalizedHost = _normalizeHost(probe.host);
      final String groupKey = _probeGroupKey(probe, successfulHosts);
      probesByGroup
          .putIfAbsent(groupKey, () => <HostProbeRecord>[])
          .add(
            HostProbeRecord(
              host: normalizedHost,
              success: probe.success,
              latencyMs: probe.latencyMs,
              statusCode: probe.statusCode,
              addressSignature: probe.addressSignature,
            ),
          );
    }
    final List<_HostAliasGroup> groups = <_HostAliasGroup>[];
    for (final List<HostProbeRecord> groupedProbes in probesByGroup.values) {
      final List<String> groupedHosts =
          _mergeHosts(groupedProbes.map((HostProbeRecord probe) => probe.host))
            ..sort((String left, String right) {
              final int leftIndex = preferenceIndex[left] ?? 1 << 30;
              final int rightIndex = preferenceIndex[right] ?? 1 << 30;
              if (leftIndex != rightIndex) {
                return leftIndex.compareTo(rightIndex);
              }
              return left.compareTo(right);
            });
      final String primaryHost = groupedHosts.first;
      final int bestLatencyMs = groupedProbes.fold<int>(
        groupedProbes.first.latencyMs,
        (int current, HostProbeRecord probe) =>
            probe.latencyMs < current ? probe.latencyMs : current,
      );
      groups.add(
        _HostAliasGroup(
          primaryHost: primaryHost,
          aliases: <String>[
            for (final String host in groupedHosts)
              if (host != primaryHost) host,
          ],
          bestLatencyMs: bestLatencyMs,
          preferenceIndex: preferenceIndex[primaryHost] ?? 1 << 30,
        ),
      );
    }
    groups.sort((_HostAliasGroup left, _HostAliasGroup right) {
      if (left.bestLatencyMs != right.bestLatencyMs) {
        return left.bestLatencyMs.compareTo(right.bestLatencyMs);
      }
      if (left.preferenceIndex != right.preferenceIndex) {
        return left.preferenceIndex.compareTo(right.preferenceIndex);
      }
      return left.primaryHost.compareTo(right.primaryHost);
    });
    return groups;
  }

  String _probeGroupKey(HostProbeRecord probe, Set<String> successfulHosts) {
    final String normalizedHost = _normalizeHost(probe.host);
    final String? pairKey = _wwwPairGroupKey(normalizedHost, successfulHosts);
    if (pairKey != null) {
      return pairKey;
    }
    final String? normalizedSignature = _normalizeAddressSignature(
      probe.addressSignature,
    );
    if (normalizedSignature != null) {
      return 'ip:$normalizedSignature';
    }
    return 'host:$normalizedHost';
  }

  String? _wwwPairGroupKey(String host, Set<String> successfulHosts) {
    final String normalizedHost = _normalizeHost(host);
    if (normalizedHost.isEmpty) {
      return null;
    }
    if (normalizedHost.startsWith('www.')) {
      final String bareHost = normalizedHost.substring(4);
      if (bareHost.isNotEmpty && successfulHosts.contains(bareHost)) {
        return 'pair:$bareHost';
      }
      return null;
    }
    final String wwwHost = 'www.$normalizedHost';
    if (successfulHosts.contains(wwwHost)) {
      return 'pair:$normalizedHost';
    }
    return null;
  }

  HostProbeRecord? _probeForHost(String host) {
    final String normalizedHost = _normalizeHost(host);
    return _snapshot?.probes.cast<HostProbeRecord?>().firstWhere(
      (HostProbeRecord? probe) =>
          probe != null && _normalizeHost(probe.host) == normalizedHost,
      orElse: () => null,
    );
  }

  List<HostProbeRecord> _upsertProbe(
    HostProbeRecord probe,
    List<HostProbeRecord> probes,
  ) {
    final String normalizedHost = _normalizeHost(probe.host);
    final List<HostProbeRecord> updated = <HostProbeRecord>[probe];
    for (final HostProbeRecord candidate in probes) {
      if (_normalizeHost(candidate.host) == normalizedHost) {
        continue;
      }
      updated.add(candidate);
    }
    return _sortProbes(updated);
  }

  String _selectAutomaticHost(List<HostProbeRecord> ranked) {
    final HostProbeRecord? nextHost = ranked
        .cast<HostProbeRecord?>()
        .firstWhere(
          (HostProbeRecord? probe) => probe != null && probe.success,
          orElse: () => null,
        );
    if (nextHost != null) {
      return _normalizeHost(nextHost.host);
    }
    final List<String> fallbackHosts = _mergeHosts(<String>[
      ..._candidateHosts,
      _currentHost,
      if (_sessionPinnedHost != null) _sessionPinnedHost!,
      ..._seedHosts,
    ]);
    return fallbackHosts.isEmpty ? '' : fallbackHosts.first;
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

  static List<String> _buildDefaultCandidateHosts() {
    return _normalizeHosts(<String>[
      'www.2026copy.com',
      '2026copy.com',
      'www.2025copy.com',
      '2025copy.com',
      'www.copy20.com',
      'copy20.com',
      'www.mangacopy.com',
      'mangacopy.com',
      'copy2000.site',
      'www.copy2000.site',
      'copy-manga.com',
      'www.copy-manga.com',
      'copy2000.online',
      'www.copy2000.online',
      'www.2027copy.com',
      '2027copy.com',
      'www.2024copy.com',
      '2024copy.com',
      'www.copymanga.tv',
      'copymanga.tv',
    ]);
  }

  Future<List<String>> _lookupHostAddresses(String host) async {
    if (_addressLookup != null) {
      return _normalizeAddresses(await _addressLookup(host));
    }
    final List<InternetAddress> addresses = await InternetAddress.lookup(
      host,
    ).timeout(connectTimeout);
    return _normalizeAddresses(
      addresses
          .where(
            (InternetAddress address) =>
                address.type == InternetAddressType.IPv4,
          )
          .map((InternetAddress address) => address.address),
    );
  }

  Future<String?> _resolveAddressSignature(String host) async {
    final String normalizedHost = _normalizeHost(host);
    if (normalizedHost.isEmpty) {
      return null;
    }
    final String? cached = _addressSignatureCache[normalizedHost];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    try {
      final String? signature = _signatureForAddresses(
        await _lookupHostAddresses(normalizedHost),
      );
      if (signature != null) {
        _addressSignatureCache[normalizedHost] = signature;
      }
      return signature;
    } catch (_) {
      return null;
    }
  }

  static List<String> _normalizeAddresses(Iterable<String> addresses) {
    final List<String> values = <String>[];
    final Set<String> seen = <String>{};
    for (final String address in addresses) {
      final String normalized = address.trim();
      if (normalized.isEmpty || !seen.add(normalized)) {
        continue;
      }
      values.add(normalized);
    }
    values.sort();
    return values;
  }

  static String? _signatureForAddresses(Iterable<String> addresses) {
    final List<String> normalized = _normalizeAddresses(addresses);
    if (normalized.isEmpty) {
      return null;
    }
    return normalized.join('|');
  }

  static String? _normalizeAddressSignature(String? value) {
    final String normalized = (value ?? '').trim();
    if (normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  static List<String> _normalizeHosts(Iterable<String> hosts) {
    final List<String> values = <String>[];
    final Set<String> seenHosts = <String>{};
    for (final String host in hosts) {
      final String normalizedHost = _normalizeHost(host);
      if (normalizedHost.isEmpty || !seenHosts.add(normalizedHost)) {
        continue;
      }
      values.add(normalizedHost);
    }
    return values;
  }

  static List<String> _mergeHosts(Iterable<String> hosts) {
    return _normalizeHosts(hosts);
  }

  static String _firstHost(Iterable<String> hosts) {
    final List<String> normalizedHosts = _normalizeHosts(hosts);
    return normalizedHosts.isEmpty ? '' : normalizedHosts.first;
  }

  static bool _looksLikeSupportedHome(String body) {
    final String normalized = body.toLowerCase();
    return normalized.contains('content-box') &&
        normalized.contains('swiperlist') &&
        normalized.contains('comicrank');
  }
}
