import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:reader/services/host_settings_store.dart';
import 'package:reader/services/network_client.dart';
import 'package:reader/services/quic_http_client.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

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

class HostManager extends ChangeNotifier {
  HostManager({
    http.Client? client,
    List<String>? candidateHosts,
    HostDirectoryProvider? directoryProvider,
    HostNowProvider? now,
    HostProbeRunner? probeRunner,
    HostConnectivityRunner? connectivityRunner,
    HostAddressLookup? addressLookup,
    HostSettingsStore? hostSettingsStore,
    sqflite.DatabaseFactory? databaseFactory,
    String userAgent = defaultDesktopUserAgent,
  }) : _client = client ?? AppHttpClientFactory.create(),
       _defaultHosts = normalizeHosts(
         candidateHosts ?? _buildDefaultCandidateHosts(),
       ),
       _candidateHosts = const <String>[],
       _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _hostSettingsStore =
           hostSettingsStore ??
           HostSettingsStore(
             directoryProvider:
                 directoryProvider ?? getApplicationSupportDirectory,
             databaseFactory: databaseFactory,
           ),
       _now = now ?? DateTime.now,
       _probeRunner = probeRunner,
       _connectivityRunner = connectivityRunner,
       _addressLookup = addressLookup,
       _userAgent = userAgent;

  static final HostManager instance = HostManager();

  static const Duration probeCacheTtl = Duration(hours: 12);
  static const Duration probeTimeout = Duration(seconds: 3);
  static const Duration connectTimeout = Duration(seconds: 2);

  final http.Client _client;
  final List<String> _defaultHosts;
  late List<String> _seedHosts = List.unmodifiable(_defaultHosts);
  late Set<String> _allowedHosts = Set.unmodifiable(_seedHosts);
  List<String> _candidateHosts;
  final HostDirectoryProvider _directoryProvider;
  final HostSettingsStore _hostSettingsStore;
  final HostNowProvider _now;
  final HostProbeRunner? _probeRunner;
  final HostConnectivityRunner? _connectivityRunner;
  final HostAddressLookup? _addressLookup;
  final String _userAgent;

  Future<void>? _initialization;
  Future<void>? _probeRefresh;
  HostProbeSnapshot? _snapshot;
  late String _currentHost = _seedHosts.firstOrNull ?? '';
  String? _sessionPinnedHost;
  Map<String, List<String>> _candidateHostAliases =
      const <String, List<String>>{};

  List<String> get candidateHosts => _candidateHosts;

  List<String> get knownHosts => _seedHosts;
  Map<String, List<String>> get candidateHostAliases => _candidateHostAliases;
  Set<String> get allowedHosts => _allowedHosts;

  String get currentHost => _sessionPinnedHost ?? _currentHost;

  Uri? _baseUri;
  Uri get baseUri {
    final host = currentHost;
    final cached = _baseUri;
    if (cached != null && cached.host == host) return cached;
    return _baseUri = Uri.parse('https://$host/');
  }

  HostProbeSnapshot? get probeSnapshot => _snapshot;

  String? get sessionPinnedHost => _sessionPinnedHost;

  Future<void> ensureInitialized() {
    return _initialization ??= _initialize();
  }

  Future<void> close() async {
    try {
      await _probeRefresh;
    } catch (_) {
      // 关闭时忽略后台测速失败。
    }
    _initialization = null;
    _probeRefresh = null;
    _snapshot = null;
    _candidateHosts = const <String>[];
    _candidateHostAliases = const <String, List<String>>{};
    _sessionPinnedHost = null;
    notifyListeners();
    await _hostSettingsStore.close();
    _client.close();
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
        _snapshot!.probes.isNotEmpty &&
        _now().difference(_snapshot!.checkedAt) < probeCacheTtl) {
      _updateCandidates(_snapshot!.probes);
      return;
    }
    final List<String> hostsToProbe = knownHosts;
    final List<HostProbeRecord> probes = hostsToProbe.isEmpty
        ? const <HostProbeRecord>[]
        : await Future.wait(hostsToProbe.map(_probeKnownHost));
    final List<HostProbeRecord> ranked = _sortProbes(probes);
    _updateCandidates(ranked);
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
    await _publishSnapshot();
  }

  Future<void> pinSessionHost(String host) async {
    await ensureInitialized();
    final String normalizedHost = normalizeHost(host);
    if (normalizedHost.isEmpty) {
      throw StateError('域名不能为空。');
    }
    if (!_isActiveRuntimeHost(normalizedHost)) {
      throw StateError('域名不存在。');
    }
    final HostProbeRecord? cachedProbe = _probeForHost(normalizedHost);
    final HostProbeRecord probe =
        cachedProbe ?? await _probeSelectableHost(normalizedHost);
    _sessionPinnedHost = normalizedHost;
    _currentHost = normalizedHost;
    _snapshot = HostProbeSnapshot(
      selectedHost: (_snapshot?.selectedHost ?? '').trim().isEmpty
          ? normalizedHost
          : normalizeHost(_snapshot!.selectedHost),
      checkedAt: _now(),
      probes: _upsertProbe(
        probe,
        _snapshot?.probes ?? const <HostProbeRecord>[],
      ),
      sessionPinnedHost: _sessionPinnedHost,
    );
    _updateCandidates(_snapshot!.probes);
    await _publishSnapshot();
  }

  Future<String> addCustomHost(String value) async {
    await ensureInitialized();
    final String normalizedHost = _normalizeCustomHostInput(value);
    if (normalizedHost.isEmpty) {
      throw StateError('域名不能为空。');
    }
    if (!_isValidHostName(normalizedHost)) {
      throw StateError('域名格式不正确。');
    }
    await _hostSettingsStore.addCustomHost(normalizedHost);
    await _reloadStoredHosts();
    notifyListeners();
    return normalizedHost;
  }

  Future<void> deleteHost(String host) async {
    await ensureInitialized();
    final String normalizedHost = normalizeHost(host);
    if (normalizedHost.isEmpty) {
      throw StateError('域名不能为空。');
    }
    if (!_isActiveRuntimeHost(normalizedHost)) {
      throw StateError('域名不存在。');
    }
    final List<String> remainingHosts = _seedHosts
        .where((String host) => host != normalizedHost)
        .toList(growable: false);
    if (remainingHosts.isEmpty) {
      throw StateError('至少保留一个域名。');
    }

    await _hostSettingsStore.deleteHost(normalizedHost);
    await _reloadStoredHosts();

    if (normalizeHost(_sessionPinnedHost ?? '') == normalizedHost ||
        !_isActiveRuntimeHost(_sessionPinnedHost ?? '')) {
      _sessionPinnedHost = null;
    }
    if (normalizeHost(_currentHost) == normalizedHost ||
        !_isActiveRuntimeHost(_currentHost)) {
      _currentHost = _seedHosts.firstOrNull ?? '';
    }
    final List<HostProbeRecord> probes = _activeProbes(
      _snapshot?.probes ?? const <HostProbeRecord>[],
    );
    _updateCandidates(probes);
    _snapshot = HostProbeSnapshot(
      selectedHost: _isActiveRuntimeHost(_snapshot?.selectedHost ?? '')
          ? normalizeHost(_snapshot!.selectedHost)
          : _currentHost,
      checkedAt: _snapshot?.checkedAt ?? _now(),
      probes: probes,
      sessionPinnedHost: _sessionPinnedHost,
    );
    await _publishSnapshot();
  }

  Future<void> clearSessionPin() async {
    await ensureInitialized();
    _sessionPinnedHost = null;
    await _persistCurrentState();
  }

  Future<String> failover({
    Iterable<String> exclude = const <String>[],
    bool refresh = true,
  }) async {
    // 必须在探测之前快照：_refreshProbes 会把 _currentHost 改成新的最优域名，
    // 探测后再读会把刚选出的最优解错误地排除掉。
    final String failingHost = normalizeHost(currentHost);
    if (refresh) await refreshProbes(force: true);
    final Set<String> excludedHosts = exclude.map(normalizeHost).toSet()
      ..add(failingHost);
    final List<HostProbeRecord> ranked = _sortProbes(_snapshot?.probes ?? []);
    // 同一 alias 组（www/裸域、同 IP 签名）指向同一后端，转移到组内成员等于没转移，
    // 所以优先整组排除。但候选域名可能全落在同一组（同一 CDN），排干净就无处可去，
    // 因此这只是偏好：组外选不到时退回只排除失败域名本身，避免 failover 变成空操作。
    final Set<String> aliasExcludedHosts = <String>{...excludedHosts};
    for (final _HostAliasGroup group in _buildHostAliasGroups(ranked)) {
      final bool groupContainsFailingHost =
          group.primaryHost == failingHost ||
          group.aliases.contains(failingHost);
      if (groupContainsFailingHost) {
        aliasExcludedHosts
          ..add(group.primaryHost)
          ..addAll(group.aliases);
      }
    }
    final HostProbeRecord? nextHost =
        _firstUsableProbe(ranked, aliasExcludedHosts) ??
        _firstUsableProbe(ranked, excludedHosts);
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

  HostProbeRecord? _firstUsableProbe(
    List<HostProbeRecord> ranked,
    Set<String> excludedHosts,
  ) {
    return ranked.cast<HostProbeRecord?>().firstWhere((HostProbeRecord? probe) {
      return probe != null &&
          probe.success &&
          !excludedHosts.contains(normalizeHost(probe.host));
    }, orElse: () => null);
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
    final String host = uri.host.toLowerCase();
    final String activeHost = currentHost;
    if (host == activeHost && uri.scheme == 'https' && uri.port == 443) {
      return uri;
    }
    if (host != activeHost && !allowedHosts.contains(host)) return uri;
    return uri.replace(scheme: 'https', host: activeHost, port: 443);
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
    final String host = uri.host.toLowerCase();
    return host == currentHost || allowedHosts.contains(host);
  }

  Future<void> _initialize() async {
    _snapshot = await _loadSnapshot();
    await _hostSettingsStore.ensureInitialized();
    await _hostSettingsStore.insertMissingHosts({
      ..._defaultHosts,
      ..._snapshotHosts(_snapshot),
    });
    await _reloadStoredHosts();
    if (_snapshot != null) {
      _currentHost =
          _snapshot!.selectedHost.isEmpty ||
              !_isActiveRuntimeHost(_snapshot!.selectedHost)
          ? _currentHost
          : normalizeHost(_snapshot!.selectedHost);
      _sessionPinnedHost = _snapshot!.sessionPinnedHost == null
          ? null
          : _isActiveRuntimeHost(_snapshot!.sessionPinnedHost!)
          ? normalizeHost(_snapshot!.sessionPinnedHost!)
          : null;
      _snapshot = HostProbeSnapshot(
        selectedHost: _isActiveRuntimeHost(_snapshot!.selectedHost)
            ? normalizeHost(_snapshot!.selectedHost)
            : _currentHost,
        checkedAt: _snapshot!.checkedAt,
        probes: _activeProbes(_snapshot!.probes),
        sessionPinnedHost: _sessionPinnedHost,
      );
      _updateCandidates(_snapshot!.probes);
    }
    if (!_isActiveRuntimeHost(_currentHost)) {
      _currentHost = _seedHosts.firstOrNull ?? '';
    }
    notifyListeners();
    // 冷启动先复用上次可用域名，探测放到后台。
  }

  Future<void> _reloadStoredHosts() async {
    final stored = await _hostSettingsStore.activeHosts();
    _seedHosts = List.unmodifiable(stored.isEmpty ? _defaultHosts : stored);
    _allowedHosts = Set.unmodifiable(_seedHosts);
  }

  List<String> _snapshotHosts(HostProbeSnapshot? snapshot) {
    if (snapshot == null) {
      return const <String>[];
    }
    return normalizeHosts(<String>[
      snapshot.selectedHost,
      if ((snapshot.sessionPinnedHost ?? '').trim().isNotEmpty)
        snapshot.sessionPinnedHost!,
      for (final HostProbeRecord probe in snapshot.probes) probe.host,
    ]);
  }

  List<HostProbeRecord> _activeProbes(List<HostProbeRecord> probes) {
    return probes
        .where((HostProbeRecord probe) => _isActiveRuntimeHost(probe.host))
        .toList(growable: false);
  }

  bool _isActiveRuntimeHost(String host) {
    final String normalizedHost = normalizeHost(host);
    return normalizedHost.isNotEmpty && _allowedHosts.contains(normalizedHost);
  }

  Future<HostProbeRecord> _probeKnownHost(String host) async {
    final String normalizedHost = normalizeHost(host);
    if (normalizedHost.isEmpty) {
      return const HostProbeRecord(host: '', success: false, latencyMs: 999999);
    }
    if (_connectivityRunner != null &&
        !await _connectivityRunner(normalizedHost)) {
      return HostProbeRecord(
        host: normalizedHost,
        success: false,
        latencyMs: 999999,
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
      final http.Response response = await NetworkClient.get(
        _client,
        Uri.https(host, '/'),
        headers: {'User-Agent': _userAgent},
        timeout: probeTimeout,
        maxRetries: 0,
        label: 'host.probe',
      );
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

  Future<HostProbeRecord> _probeSelectableHost(String host) async {
    try {
      return await _probeKnownHost(host);
    } catch (_) {
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

  void _updateCandidates(List<HostProbeRecord> probes) {
    final aliases = {
      for (final group in _buildHostAliasGroups(probes))
        group.primaryHost: List<String>.unmodifiable(group.aliases),
    };
    _candidateHostAliases = Map.unmodifiable(aliases);
    _candidateHosts = List.unmodifiable(aliases.keys);
  }

  List<_HostAliasGroup> _buildHostAliasGroups(List<HostProbeRecord> probes) {
    final List<HostProbeRecord> successful = probes
        .where(
          (HostProbeRecord probe) =>
              probe.success && normalizeHost(probe.host).isNotEmpty,
        )
        .toList(growable: false);
    if (successful.isEmpty) {
      return const <_HostAliasGroup>[];
    }
    final Set<String> successfulHosts = <String>{
      for (final HostProbeRecord probe in successful) normalizeHost(probe.host),
    };
    final List<String> preferenceOrder = normalizeHosts(<String>[
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
      final String normalizedHost = normalizeHost(probe.host);
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
          normalizeHosts(
            groupedProbes.map((HostProbeRecord probe) => probe.host),
          )..sort((String left, String right) {
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
    final String normalizedHost = normalizeHost(probe.host);
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
    final String normalizedHost = normalizeHost(host);
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
    final String normalizedHost = normalizeHost(host);
    return _snapshot?.probes.cast<HostProbeRecord?>().firstWhere(
      (HostProbeRecord? probe) =>
          probe != null && normalizeHost(probe.host) == normalizedHost,
      orElse: () => null,
    );
  }

  List<HostProbeRecord> _upsertProbe(
    HostProbeRecord probe,
    List<HostProbeRecord> probes,
  ) {
    final String normalizedHost = normalizeHost(probe.host);
    final List<HostProbeRecord> updated = <HostProbeRecord>[probe];
    for (final HostProbeRecord candidate in probes) {
      if (normalizeHost(candidate.host) == normalizedHost) {
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
      return normalizeHost(nextHost.host);
    }
    final List<String> fallbackHosts = normalizeHosts(<String>[
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
    await _publishSnapshot();
  }

  Future<void> _publishSnapshot() async {
    notifyListeners();
    try {
      final File file = await _snapshotFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(_snapshot?.toJson() ?? {}),
      );
    } catch (_) {
      // 持久化失败不影响当前域名选择。
    }
  }

  static String _normalizeCustomHostInput(String value) {
    String input = value.trim();
    if (input.isEmpty) {
      return '';
    }
    Uri? uri = Uri.tryParse(input);
    if (uri != null && uri.hasScheme) {
      input = uri.host;
    } else {
      if (input.startsWith('//')) {
        uri = Uri.tryParse('https:$input');
        input = uri?.host ?? input;
      } else {
        final int pathStart = input.indexOf(RegExp(r'[/\?#]'));
        if (pathStart >= 0) {
          input = input.substring(0, pathStart);
        }
        final int userInfoEnd = input.lastIndexOf('@');
        if (userInfoEnd >= 0) {
          input = input.substring(userInfoEnd + 1);
        }
        final int portStart = input.lastIndexOf(':');
        if (portStart > 0 && input.indexOf(':') == portStart) {
          input = input.substring(0, portStart);
        }
      }
    }
    return normalizeHost(input);
  }

  static bool _isValidHostName(String host) {
    final String normalizedHost = normalizeHost(host);
    if (normalizedHost.isEmpty ||
        normalizedHost.length > 253 ||
        normalizedHost.contains('..') ||
        normalizedHost.contains(' ') ||
        normalizedHost.startsWith('.') ||
        normalizedHost.endsWith('.')) {
      return false;
    }
    final RegExp labelPattern = RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$');
    final List<String> labels = normalizedHost.split('.');
    return labels.every(
      (String label) =>
          label.isNotEmpty &&
          label.length <= 63 &&
          labelPattern.hasMatch(label),
    );
  }

  static List<String> _buildDefaultCandidateHosts() {
    return normalizeHosts(<String>[
      'www.2026copy.com',
      '2026copy.com',
      'www.2025copy.com',
      '2025copy.com',
      'www.mangacopy.com',
      'mangacopy.com',
      'www.copy3000.com',
      'www.2027copy.com',
      '2027copy.com',
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
    final String normalizedHost = normalizeHost(host);
    if (normalizedHost.isEmpty) {
      return null;
    }
    try {
      return _signatureForAddresses(await _lookupHostAddresses(normalizedHost));
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

  static bool _looksLikeSupportedHome(String body) {
    final String normalized = body.toLowerCase();
    return normalized.contains('content-box') &&
        normalized.contains('swiperlist') &&
        normalized.contains('comicrank');
  }
}
