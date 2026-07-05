import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:reader/services/host_settings_store.dart';
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

@immutable
class HostSiteState {
  const HostSiteState({
    required this.siteKey,
    required this.label,
    required this.currentHost,
    this.knownHosts = const <String>[],
    this.candidateHosts = const <String>[],
    this.candidateHostAliases = const <String, List<String>>{},
    this.snapshot,
  });

  final String siteKey;
  final String label;
  final String currentHost;
  final List<String> knownHosts;
  final List<String> candidateHosts;
  final Map<String, List<String>> candidateHostAliases;
  final HostProbeSnapshot? snapshot;
}

class HostManager {
  HostManager({
    http.Client? client,
    List<String>? candidateHosts,
    Map<String, List<String>>? candidateHostsBySite,
    String initialSiteKey = copySiteKey,
    HostDirectoryProvider? directoryProvider,
    HostNowProvider? now,
    HostProbeRunner? probeRunner,
    HostConnectivityRunner? connectivityRunner,
    HostAddressLookup? addressLookup,
    HostSettingsStore? hostSettingsStore,
    sqflite.DatabaseFactory? databaseFactory,
    String userAgent = defaultDesktopUserAgent,
  }) : _client = client ?? AppHttpClientFactory.create(),
       _defaultHostsBySite = _buildInitialCandidateHostsBySite(
         candidateHosts: candidateHosts,
         candidateHostsBySite: candidateHostsBySite,
       ),
       _seedHostsBySite = _buildInitialCandidateHostsBySite(
         candidateHosts: candidateHosts,
         candidateHostsBySite: candidateHostsBySite,
       ),
       _candidateHostsBySite = const <String, List<String>>{},
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
       _userAgent = userAgent,
       _currentHostBySite = _firstHostsBySite(
         _buildInitialCandidateHostsBySite(
           candidateHosts: candidateHosts,
           candidateHostsBySite: candidateHostsBySite,
         ),
       ),
       _currentSiteKey = _normalizeSiteKey(
         initialSiteKey,
         knownSiteKeys: _buildInitialCandidateHostsBySite(
           candidateHosts: candidateHosts,
           candidateHostsBySite: candidateHostsBySite,
         ).keys,
       );

  static final HostManager instance = HostManager();

  static const String copySiteKey = 'copy';
  static const String hotSiteKey = 'hot';

  static const Duration probeCacheTtl = Duration(hours: 12);
  static const Duration probeTimeout = Duration(seconds: 3);
  static const Duration connectTimeout = Duration(seconds: 2);

  final http.Client _client;
  final Map<String, List<String>> _defaultHostsBySite;
  Map<String, List<String>> _seedHostsBySite;
  Map<String, List<String>> _candidateHostsBySite;
  final HostDirectoryProvider _directoryProvider;
  final HostSettingsStore _hostSettingsStore;
  final HostNowProvider _now;
  final HostProbeRunner? _probeRunner;
  final HostConnectivityRunner? _connectivityRunner;
  final HostAddressLookup? _addressLookup;
  final String _userAgent;

  Future<void>? _initialization;
  final Map<String, Future<void>> _probeRefreshBySite =
      <String, Future<void>>{};
  Map<String, HostProbeSnapshot> _snapshotsBySite =
      <String, HostProbeSnapshot>{};
  final Map<String, String> _currentHostBySite;
  Map<String, String?> _sessionPinnedHostBySite = <String, String?>{};
  Map<String, Map<String, List<String>>> _candidateHostAliasesBySite =
      const <String, Map<String, List<String>>>{};
  String _currentSiteKey;
  final Map<String, String> _addressSignatureCache = <String, String>{};

  String get currentSiteKey => _currentSiteKey;

  List<String> get availableSiteKeys =>
      List<String>.unmodifiable(_defaultHostsBySite.keys);

  List<HostSiteState> get siteStates {
    return <HostSiteState>[
      for (final String siteKey in availableSiteKeys)
        HostSiteState(
          siteKey: siteKey,
          label: siteLabel(siteKey),
          currentHost: currentHostForSite(siteKey),
          knownHosts: knownHostsForSite(siteKey),
          candidateHosts: candidateHostsForSite(siteKey),
          candidateHostAliases: candidateHostAliasesForSite(siteKey),
          snapshot: probeSnapshotForSite(siteKey),
        ),
    ];
  }

  List<String> get candidateHosts => candidateHostsForSite(_currentSiteKey);

  List<String> get knownHosts => knownHostsForSite(_currentSiteKey);

  List<String> knownHostsForSite(String siteKey) => List<String>.unmodifiable(
    _normalizeHosts(<String>[
      ..._seedHostsForSite(siteKey),
      if (_isActiveRuntimeHost(_currentHostForSite(siteKey), siteKey: siteKey))
        _currentHostForSite(siteKey),
      if (_sessionPinnedHostForSite(siteKey) != null &&
          _isActiveRuntimeHost(
            _sessionPinnedHostForSite(siteKey)!,
            siteKey: siteKey,
          ))
        _sessionPinnedHostForSite(siteKey)!,
      if ((_snapshotForSite(siteKey)?.selectedHost ?? '').trim().isNotEmpty &&
          _isActiveRuntimeHost(
            _snapshotForSite(siteKey)!.selectedHost,
            siteKey: siteKey,
          ))
        _snapshotForSite(siteKey)!.selectedHost,
      for (final HostProbeRecord probe
          in _snapshotForSite(siteKey)?.probes ?? const <HostProbeRecord>[])
        if (_isActiveRuntimeHost(probe.host, siteKey: siteKey)) probe.host,
    ]),
  );

  List<String> candidateHostsForSite(String siteKey) =>
      List<String>.unmodifiable(
        _candidateHostsBySite[_normalizeKnownSiteKey(siteKey)] ??
            const <String>[],
      );

  Map<String, List<String>> get candidateHostAliases =>
      candidateHostAliasesForSite(_currentSiteKey);

  Map<String, List<String>> candidateHostAliasesForSite(String siteKey) {
    final Map<String, List<String>> aliases =
        _candidateHostAliasesBySite[_normalizeKnownSiteKey(siteKey)] ??
        const <String, List<String>>{};
    return Map<String, List<String>>.unmodifiable(
      aliases.map(
        (String host, List<String> aliases) =>
            MapEntry(host, List<String>.unmodifiable(aliases)),
      ),
    );
  }

  Set<String> get allowedHosts => <String>{
    ..._seedHostsForSite(_currentSiteKey),
    ...candidateHostsForSite(_currentSiteKey),
    if (_isActiveRuntimeHost(_currentHostForSite(_currentSiteKey)))
      _currentHostForSite(_currentSiteKey),
    if ((_sessionPinnedHostForSite(_currentSiteKey) ?? '').trim().isNotEmpty)
      if (_isActiveRuntimeHost(_sessionPinnedHostForSite(_currentSiteKey)!))
        _normalizeHost(_sessionPinnedHostForSite(_currentSiteKey)!),
    if ((_snapshotForSite(_currentSiteKey)?.selectedHost ?? '')
        .trim()
        .isNotEmpty)
      if (_isActiveRuntimeHost(_snapshotForSite(_currentSiteKey)!.selectedHost))
        _normalizeHost(_snapshotForSite(_currentSiteKey)!.selectedHost),
    for (final HostProbeRecord probe
        in _snapshotForSite(_currentSiteKey)?.probes ??
            const <HostProbeRecord>[])
      if (_isActiveRuntimeHost(probe.host)) _normalizeHost(probe.host),
  };

  String get currentHost => currentHostForSite(_currentSiteKey);

  String currentHostForSite(String siteKey) {
    final String normalizedSiteKey = _normalizeKnownSiteKey(siteKey);
    return _sessionPinnedHostForSite(normalizedSiteKey) ??
        _currentHostForSite(normalizedSiteKey);
  }

  Uri get baseUri => Uri.parse('https://$currentHost/');

  HostProbeSnapshot? get probeSnapshot => probeSnapshotForSite(_currentSiteKey);

  HostProbeSnapshot? probeSnapshotForSite(String siteKey) =>
      _snapshotForSite(siteKey);

  String? get sessionPinnedHost => sessionPinnedHostForSite(_currentSiteKey);

  String? sessionPinnedHostForSite(String siteKey) =>
      _sessionPinnedHostForSite(siteKey);

  @visibleForTesting
  HostProbeSnapshot? get snapshot => _snapshotForSite(_currentSiteKey);

  Future<void> ensureInitialized() {
    return _initialization ??= _initialize();
  }

  Future<void> close() async {
    try {
      await Future.wait(_probeRefreshBySite.values);
    } catch (_) {
      // 关闭时忽略后台测速失败。
    }
    _initialization = null;
    _probeRefreshBySite.clear();
    _snapshotsBySite = <String, HostProbeSnapshot>{};
    _candidateHostsBySite = const <String, List<String>>{};
    _candidateHostAliasesBySite = const <String, Map<String, List<String>>>{};
    _sessionPinnedHostBySite = <String, String?>{};
    await _hostSettingsStore.close();
    _client.close();
  }

  Future<void> switchSite(String siteKey) async {
    await ensureInitialized();
    final String normalizedSiteKey = _normalizeKnownSiteKey(siteKey);
    _currentSiteKey = normalizedSiteKey;
    await _persistCurrentState(siteKey: normalizedSiteKey);
  }

  Future<void> refreshProbes({bool force = false, String? siteKey}) async {
    if (_initialization == null) {
      await ensureInitialized();
    }
    final String targetSiteKey = _effectiveSiteKey(siteKey);
    final Future<void>? activeRefresh = _probeRefreshBySite[targetSiteKey];
    if (activeRefresh != null) {
      return activeRefresh;
    }
    final Future<void> refresh = _refreshProbes(
      force: force,
      siteKey: targetSiteKey,
    );
    _probeRefreshBySite[targetSiteKey] = refresh;
    return refresh.whenComplete(() {
      if (identical(_probeRefreshBySite[targetSiteKey], refresh)) {
        _probeRefreshBySite.remove(targetSiteKey);
      }
    });
  }

  Future<void> _refreshProbes({required bool force, String? siteKey}) async {
    if (_initialization == null) {
      await ensureInitialized();
    }
    final String targetSiteKey = _effectiveSiteKey(siteKey);
    if (siteKey != null) {
      _currentSiteKey = targetSiteKey;
    }
    final HostProbeSnapshot? currentSnapshot = _snapshotForSite(targetSiteKey);
    if (!force &&
        currentSnapshot != null &&
        _now().difference(currentSnapshot.checkedAt) < probeCacheTtl) {
      _candidateHostsBySite = _copyStringListMapWith(
        _candidateHostsBySite,
        targetSiteKey,
        _successfulProbeHosts(currentSnapshot.probes, siteKey: targetSiteKey),
      );
      _candidateHostAliasesBySite = _copyAliasMapWith(
        _candidateHostAliasesBySite,
        targetSiteKey,
        _buildCandidateHostAliases(
          currentSnapshot.probes,
          siteKey: targetSiteKey,
        ),
      );
      return;
    }
    final List<String> hostsToProbe = knownHostsForSite(targetSiteKey);
    final List<HostProbeRecord> probes = hostsToProbe.isEmpty
        ? const <HostProbeRecord>[]
        : await Future.wait(hostsToProbe.map(_probeKnownHost));
    final List<HostProbeRecord> ranked = _sortProbes(probes);
    _candidateHostsBySite = _copyStringListMapWith(
      _candidateHostsBySite,
      targetSiteKey,
      _successfulProbeHosts(ranked, siteKey: targetSiteKey),
    );
    _candidateHostAliasesBySite = _copyAliasMapWith(
      _candidateHostAliasesBySite,
      targetSiteKey,
      _buildCandidateHostAliases(ranked, siteKey: targetSiteKey),
    );
    final String nextHost = _selectAutomaticHost(
      ranked,
      siteKey: targetSiteKey,
    );
    if (nextHost.isNotEmpty) {
      _currentHostBySite[targetSiteKey] = nextHost;
    }
    final HostProbeSnapshot snapshot = HostProbeSnapshot(
      selectedHost: nextHost.isEmpty
          ? _currentHostForSite(targetSiteKey)
          : nextHost,
      checkedAt: _now(),
      probes: ranked,
      sessionPinnedHost: _sessionPinnedHostForSite(targetSiteKey),
    );
    _snapshotsBySite = Map<String, HostProbeSnapshot>.from(_snapshotsBySite)
      ..[targetSiteKey] = snapshot;
    await _saveSnapshot();
  }

  Future<void> pinSessionHost(String host, {String? siteKey}) async {
    await ensureInitialized();
    final String targetSiteKey = _effectiveSiteKey(siteKey);
    if (siteKey != null) {
      _currentSiteKey = targetSiteKey;
    }
    final String normalizedHost = _normalizeHost(host);
    if (normalizedHost.isEmpty) {
      throw StateError('域名不能为空。');
    }
    if (!_isActiveRuntimeHost(normalizedHost, siteKey: targetSiteKey)) {
      throw StateError('域名不存在。');
    }
    final HostProbeRecord? cachedProbe = _probeForHost(
      normalizedHost,
      siteKey: targetSiteKey,
    );
    final HostProbeRecord probe =
        cachedProbe ?? await _probeSelectableHost(normalizedHost);
    _sessionPinnedHostBySite = Map<String, String?>.from(
      _sessionPinnedHostBySite,
    )..[targetSiteKey] = normalizedHost;
    _currentHostBySite[targetSiteKey] = normalizedHost;
    final HostProbeSnapshot? currentSnapshot = _snapshotForSite(targetSiteKey);
    final HostProbeSnapshot snapshot = HostProbeSnapshot(
      selectedHost: (currentSnapshot?.selectedHost ?? '').trim().isEmpty
          ? normalizedHost
          : _normalizeHost(currentSnapshot!.selectedHost),
      checkedAt: _now(),
      probes: _upsertProbe(
        probe,
        currentSnapshot?.probes ?? const <HostProbeRecord>[],
      ),
      sessionPinnedHost: _sessionPinnedHostForSite(targetSiteKey),
    );
    _snapshotsBySite = Map<String, HostProbeSnapshot>.from(_snapshotsBySite)
      ..[targetSiteKey] = snapshot;
    _candidateHostsBySite = _copyStringListMapWith(
      _candidateHostsBySite,
      targetSiteKey,
      _successfulProbeHosts(snapshot.probes, siteKey: targetSiteKey),
    );
    _candidateHostAliasesBySite = _copyAliasMapWith(
      _candidateHostAliasesBySite,
      targetSiteKey,
      _buildCandidateHostAliases(snapshot.probes, siteKey: targetSiteKey),
    );
    await _saveSnapshot();
  }

  Future<String> addCustomHost(String value, {String? siteKey}) async {
    await ensureInitialized();
    final String targetSiteKey = _effectiveSiteKey(siteKey);
    final String normalizedHost = _normalizeCustomHostInput(value);
    if (normalizedHost.isEmpty) {
      throw StateError('域名不能为空。');
    }
    if (!_isValidHostName(normalizedHost)) {
      throw StateError('域名格式不正确。');
    }
    await _hostSettingsStore.addCustomHost(
      normalizedHost,
      siteKey: targetSiteKey,
    );
    await _reloadStoredHosts();
    return normalizedHost;
  }

  Future<void> deleteHost(String host, {String? siteKey}) async {
    await ensureInitialized();
    final String targetSiteKey = _effectiveSiteKey(siteKey);
    final String normalizedHost = _normalizeHost(host);
    if (normalizedHost.isEmpty) {
      throw StateError('域名不能为空。');
    }
    if (!_isActiveRuntimeHost(normalizedHost, siteKey: targetSiteKey)) {
      throw StateError('域名不存在。');
    }
    final List<String> remainingHosts = _seedHostsForSite(
      targetSiteKey,
    ).where((String host) => host != normalizedHost).toList(growable: false);
    if (remainingHosts.isEmpty) {
      throw StateError('至少保留一个域名。');
    }

    await _hostSettingsStore.deleteHost(normalizedHost, siteKey: targetSiteKey);
    await _reloadStoredHosts();

    _candidateHostsBySite = _copyStringListMapWith(
      _candidateHostsBySite,
      targetSiteKey,
      candidateHostsForSite(targetSiteKey)
          .where(
            (String host) => _isActiveRuntimeHost(host, siteKey: targetSiteKey),
          )
          .toList(growable: false),
    );
    if (_normalizeHost(_sessionPinnedHostForSite(targetSiteKey) ?? '') ==
            normalizedHost ||
        !_isActiveRuntimeHost(
          _sessionPinnedHostForSite(targetSiteKey) ?? '',
          siteKey: targetSiteKey,
        )) {
      _sessionPinnedHostBySite = Map<String, String?>.from(
        _sessionPinnedHostBySite,
      )..[targetSiteKey] = null;
    }
    if (_normalizeHost(_currentHostForSite(targetSiteKey)) == normalizedHost ||
        !_isActiveRuntimeHost(
          _currentHostForSite(targetSiteKey),
          siteKey: targetSiteKey,
        )) {
      _currentHostBySite[targetSiteKey] = _firstHost(
        _seedHostsForSite(targetSiteKey),
      );
    }
    final List<HostProbeRecord> probes = _activeProbes(
      _snapshotForSite(targetSiteKey)?.probes ?? const <HostProbeRecord>[],
      siteKey: targetSiteKey,
    );
    _candidateHostAliasesBySite = _copyAliasMapWith(
      _candidateHostAliasesBySite,
      targetSiteKey,
      _buildCandidateHostAliases(probes, siteKey: targetSiteKey),
    );
    final HostProbeSnapshot? currentSnapshot = _snapshotForSite(targetSiteKey);
    final HostProbeSnapshot snapshot = HostProbeSnapshot(
      selectedHost:
          _isActiveRuntimeHost(
            currentSnapshot?.selectedHost ?? '',
            siteKey: targetSiteKey,
          )
          ? _normalizeHost(currentSnapshot!.selectedHost)
          : _currentHostForSite(targetSiteKey),
      checkedAt: currentSnapshot?.checkedAt ?? _now(),
      probes: probes,
      sessionPinnedHost: _sessionPinnedHostForSite(targetSiteKey),
    );
    _snapshotsBySite = Map<String, HostProbeSnapshot>.from(_snapshotsBySite)
      ..[targetSiteKey] = snapshot;
    await _saveSnapshot();
  }

  Future<void> clearSessionPin({String? siteKey}) async {
    await ensureInitialized();
    final String targetSiteKey = _effectiveSiteKey(siteKey);
    if (siteKey != null) {
      _currentSiteKey = targetSiteKey;
    }
    _sessionPinnedHostBySite = Map<String, String?>.from(
      _sessionPinnedHostBySite,
    )..[targetSiteKey] = null;
    await _persistCurrentState(siteKey: targetSiteKey);
  }

  Future<String> failover({Iterable<String> exclude = const <String>[]}) async {
    await refreshProbes(force: true);
    final Set<String> excludedHosts = exclude.map(_normalizeHost).toSet()
      ..add(_normalizeHost(currentHost));
    final List<HostProbeRecord> ranked = _sortProbes(
      _snapshotForSite(_currentSiteKey)?.probes ?? <HostProbeRecord>[],
    );
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
    _currentHostBySite[_currentSiteKey] = nextHost.host;
    if (_sessionPinnedHostForSite(_currentSiteKey) != null) {
      _sessionPinnedHostBySite = Map<String, String?>.from(
        _sessionPinnedHostBySite,
      )..[_currentSiteKey] = nextHost.host;
    }
    await _persistCurrentState(siteKey: _currentSiteKey);
    return currentHost;
  }

  Uri resolvePath(String path) {
    final String normalizedPath = path.startsWith('/')
        ? path.substring(1)
        : path;
    return baseUri.resolve(normalizedPath);
  }

  Uri rewriteInternalUriToCurrentHost(Uri uri) {
    final Uri sourceUri = uri.hasScheme ? uri : baseUri.resolveUri(uri);
    return baseUri.replace(
      path: sourceUri.path.isEmpty ? '/' : sourceUri.path,
      query: sourceUri.hasQuery ? sourceUri.query : null,
      fragment: sourceUri.hasFragment ? sourceUri.fragment : null,
    );
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
    // 多数地址已是当前域名，先用字符串短路。
    if (host != activeHost && !allowedHosts.contains(host)) {
      return uri;
    }
    return uri.replace(
      scheme: baseUri.scheme,
      host: activeHost,
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
    return true;
  }

  Future<void> _initialize() async {
    final _LoadedHostSnapshots loadedSnapshots = await _loadSnapshots();
    _snapshotsBySite = loadedSnapshots.snapshots;
    _currentSiteKey = _normalizeKnownSiteKey(
      loadedSnapshots.currentSiteKey.isEmpty
          ? _currentSiteKey
          : loadedSnapshots.currentSiteKey,
    );
    await _hostSettingsStore.ensureInitialized();
    for (final MapEntry<String, List<String>> entry
        in _defaultHostsBySite.entries) {
      await _hostSettingsStore.upsertBuiltinHosts(
        entry.value,
        siteKey: entry.key,
      );
    }
    for (final MapEntry<String, HostProbeSnapshot> entry
        in _snapshotsBySite.entries) {
      await _hostSettingsStore.upsertLegacyHosts(
        _snapshotHosts(entry.value),
        siteKey: entry.key,
      );
    }
    await _reloadStoredHosts();

    final Map<String, HostProbeSnapshot> normalizedSnapshots =
        <String, HostProbeSnapshot>{};
    final Map<String, List<String>> candidateHostsBySite =
        <String, List<String>>{};
    final Map<String, Map<String, List<String>>> aliasesBySite =
        <String, Map<String, List<String>>>{};
    final Map<String, String?> pinnedBySite = <String, String?>{};

    for (final String siteKey in availableSiteKeys) {
      final HostProbeSnapshot? snapshot = _snapshotForSite(siteKey);
      if (snapshot != null) {
        final String selectedHost =
            snapshot.selectedHost.isEmpty ||
                !_isActiveRuntimeHost(snapshot.selectedHost, siteKey: siteKey)
            ? _currentHostForSite(siteKey)
            : _normalizeHost(snapshot.selectedHost);
        _currentHostBySite[siteKey] = selectedHost;
        final String? pinnedHost = snapshot.sessionPinnedHost == null
            ? null
            : _isActiveRuntimeHost(
                snapshot.sessionPinnedHost!,
                siteKey: siteKey,
              )
            ? _normalizeHost(snapshot.sessionPinnedHost!)
            : null;
        pinnedBySite[siteKey] = pinnedHost;
        final List<HostProbeRecord> probes = _activeProbes(
          snapshot.probes,
          siteKey: siteKey,
        );
        final HostProbeSnapshot normalizedSnapshot = HostProbeSnapshot(
          selectedHost:
              _isActiveRuntimeHost(snapshot.selectedHost, siteKey: siteKey)
              ? _normalizeHost(snapshot.selectedHost)
              : _currentHostForSite(siteKey),
          checkedAt: snapshot.checkedAt,
          probes: probes,
          sessionPinnedHost: pinnedHost,
        );
        normalizedSnapshots[siteKey] = normalizedSnapshot;
        candidateHostsBySite[siteKey] = _successfulProbeHosts(
          probes,
          siteKey: siteKey,
        );
        aliasesBySite[siteKey] = _buildCandidateHostAliases(
          probes,
          siteKey: siteKey,
        );
      }
      if (!_isActiveRuntimeHost(
        _currentHostForSite(siteKey),
        siteKey: siteKey,
      )) {
        _currentHostBySite[siteKey] = _firstHost(_seedHostsForSite(siteKey));
      }
    }
    _sessionPinnedHostBySite = pinnedBySite;
    _snapshotsBySite = normalizedSnapshots;
    _candidateHostsBySite = candidateHostsBySite;
    _candidateHostAliasesBySite = aliasesBySite;
    // 冷启动先复用上次可用域名，探测放到后台。
  }

  Future<void> _reloadStoredHosts() async {
    final Map<String, List<String>> nextSeedHosts = <String, List<String>>{};
    for (final String siteKey in availableSiteKeys) {
      final List<String> activeHosts = _normalizeHosts(
        await _hostSettingsStore.activeHosts(siteKey: siteKey),
      );
      nextSeedHosts[siteKey] = activeHosts.isEmpty
          ? _defaultHostsForSite(siteKey)
          : activeHosts;
    }
    _seedHostsBySite = nextSeedHosts;
  }

  List<String> _snapshotHosts(HostProbeSnapshot? snapshot) {
    if (snapshot == null) {
      return const <String>[];
    }
    return _normalizeHosts(<String>[
      snapshot.selectedHost,
      if ((snapshot.sessionPinnedHost ?? '').trim().isNotEmpty)
        snapshot.sessionPinnedHost!,
      for (final HostProbeRecord probe in snapshot.probes) probe.host,
    ]);
  }

  List<HostProbeRecord> _activeProbes(
    List<HostProbeRecord> probes, {
    String? siteKey,
  }) {
    final String targetSiteKey = _effectiveSiteKey(siteKey);
    return probes
        .where(
          (HostProbeRecord probe) =>
              _isActiveRuntimeHost(probe.host, siteKey: targetSiteKey),
        )
        .toList(growable: false);
  }

  bool _isActiveRuntimeHost(String host, {String? siteKey}) {
    final String targetSiteKey = _effectiveSiteKey(siteKey);
    final String normalizedHost = _normalizeHost(host);
    return normalizedHost.isNotEmpty &&
        _seedHostsForSite(targetSiteKey).contains(normalizedHost);
  }

  Future<HostProbeRecord> _probeKnownHost(String host) async {
    final String normalizedHost = _normalizeHost(host);
    if (normalizedHost.isEmpty) {
      return const HostProbeRecord(host: '', success: false, latencyMs: 999999);
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

  List<String> _successfulProbeHosts(
    List<HostProbeRecord> probes, {
    String? siteKey,
  }) {
    return _buildHostAliasGroups(
      probes,
      siteKey: siteKey,
    ).map((_HostAliasGroup group) => group.primaryHost).toList(growable: false);
  }

  Map<String, List<String>> _buildCandidateHostAliases(
    List<HostProbeRecord> probes, {
    String? siteKey,
  }) {
    final Map<String, List<String>> aliases = <String, List<String>>{};
    for (final _HostAliasGroup group in _buildHostAliasGroups(
      probes,
      siteKey: siteKey,
    )) {
      aliases[group.primaryHost] = List<String>.unmodifiable(group.aliases);
    }
    return aliases;
  }

  List<_HostAliasGroup> _buildHostAliasGroups(
    List<HostProbeRecord> probes, {
    String? siteKey,
  }) {
    final String targetSiteKey = _effectiveSiteKey(siteKey);
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
    final List<String> preferenceOrder = _normalizeHosts(<String>[
      ..._seedHostsForSite(targetSiteKey),
      if (_sessionPinnedHostForSite(targetSiteKey) != null)
        _sessionPinnedHostForSite(targetSiteKey)!,
      _currentHostForSite(targetSiteKey),
      ...candidateHostsForSite(targetSiteKey),
      if ((_snapshotForSite(targetSiteKey)?.selectedHost ?? '')
          .trim()
          .isNotEmpty)
        _snapshotForSite(targetSiteKey)!.selectedHost,
      for (final HostProbeRecord probe
          in _snapshotForSite(targetSiteKey)?.probes ??
              const <HostProbeRecord>[])
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
          _normalizeHosts(
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

  HostProbeRecord? _probeForHost(String host, {String? siteKey}) {
    final String targetSiteKey = _effectiveSiteKey(siteKey);
    final String normalizedHost = _normalizeHost(host);
    return _snapshotForSite(
      targetSiteKey,
    )?.probes.cast<HostProbeRecord?>().firstWhere(
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

  String _selectAutomaticHost(List<HostProbeRecord> ranked, {String? siteKey}) {
    final String targetSiteKey = _effectiveSiteKey(siteKey);
    final HostProbeRecord? nextHost = ranked
        .cast<HostProbeRecord?>()
        .firstWhere(
          (HostProbeRecord? probe) => probe != null && probe.success,
          orElse: () => null,
        );
    if (nextHost != null) {
      return _normalizeHost(nextHost.host);
    }
    final List<String> fallbackHosts = _normalizeHosts(<String>[
      ...candidateHostsForSite(targetSiteKey),
      _currentHostForSite(targetSiteKey),
      if (_sessionPinnedHostForSite(targetSiteKey) != null)
        _sessionPinnedHostForSite(targetSiteKey)!,
      ..._seedHostsForSite(targetSiteKey),
    ]);
    return fallbackHosts.isEmpty ? '' : fallbackHosts.first;
  }

  Future<File> _snapshotFile() async {
    final Directory directory = await _directoryProvider();
    return File('${directory.path}${Platform.pathSeparator}host_probe.json');
  }

  Future<_LoadedHostSnapshots> _loadSnapshots() async {
    try {
      final File file = await _snapshotFile();
      if (!await file.exists()) {
        return const _LoadedHostSnapshots();
      }
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) {
        return const _LoadedHostSnapshots();
      }
      final Map<String, Object?> json = decoded.map(
        (Object? key, Object? value) => MapEntry(key.toString(), value),
      );
      final Object? rawSites = json['sites'];
      if (rawSites is Map) {
        final Map<String, HostProbeSnapshot> snapshots =
            <String, HostProbeSnapshot>{};
        for (final MapEntry<Object?, Object?> entry in rawSites.entries) {
          final String siteKey = _normalizeKnownSiteKey(entry.key.toString());
          final Object? value = entry.value;
          if (value is! Map) {
            continue;
          }
          snapshots[siteKey] = HostProbeSnapshot.fromJson(
            value.map(
              (Object? key, Object? value) => MapEntry(key.toString(), value),
            ),
          );
        }
        return _LoadedHostSnapshots(
          currentSiteKey: (json['currentSiteKey'] as String?)?.trim() ?? '',
          snapshots: snapshots,
        );
      }
      return _LoadedHostSnapshots(
        currentSiteKey: copySiteKey,
        snapshots: <String, HostProbeSnapshot>{
          copySiteKey: HostProbeSnapshot.fromJson(json),
        },
      );
    } catch (_) {
      return const _LoadedHostSnapshots();
    }
  }

  Future<void> _persistCurrentState({required String siteKey}) async {
    final String targetSiteKey = _normalizeKnownSiteKey(siteKey);
    final HostProbeSnapshot? snapshot = _snapshotForSite(targetSiteKey);
    _snapshotsBySite = Map<String, HostProbeSnapshot>.from(_snapshotsBySite)
      ..[targetSiteKey] = HostProbeSnapshot(
        selectedHost: _currentHostForSite(targetSiteKey),
        checkedAt: snapshot?.checkedAt ?? _now(),
        probes: snapshot?.probes ?? const <HostProbeRecord>[],
        sessionPinnedHost: _sessionPinnedHostForSite(targetSiteKey),
      );
    await _saveSnapshot();
  }

  Future<void> _saveSnapshot() async {
    try {
      final File file = await _snapshotFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(<String, Object?>{
          'currentSiteKey': _currentSiteKey,
          'sites': <String, Object?>{
            for (final MapEntry<String, HostProbeSnapshot> entry
                in _snapshotsBySite.entries)
              entry.key: entry.value.toJson(),
          },
        }),
      );
    } catch (_) {
      // 持久化失败不影响当前域名选择。
    }
  }

  String _normalizeKnownSiteKey(String? siteKey) {
    return _normalizeSiteKey(siteKey, knownSiteKeys: _defaultHostsBySite.keys);
  }

  String _effectiveSiteKey(String? siteKey) {
    final String requested = (siteKey ?? '').trim();
    return requested.isEmpty
        ? _normalizeKnownSiteKey(_currentSiteKey)
        : _normalizeKnownSiteKey(requested);
  }

  String _currentHostForSite(String siteKey) {
    final String targetSiteKey = _normalizeKnownSiteKey(siteKey);
    final String currentHost = _normalizeHost(
      _currentHostBySite[targetSiteKey] ?? '',
    );
    if (currentHost.isNotEmpty) {
      return currentHost;
    }
    final String fallbackHost = _firstHost(_seedHostsForSite(targetSiteKey));
    if (fallbackHost.isNotEmpty) {
      _currentHostBySite[targetSiteKey] = fallbackHost;
    }
    return fallbackHost;
  }

  List<String> _defaultHostsForSite(String siteKey) {
    return _defaultHostsBySite[_normalizeKnownSiteKey(siteKey)] ??
        const <String>[];
  }

  List<String> _seedHostsForSite(String siteKey) {
    return _seedHostsBySite[_normalizeKnownSiteKey(siteKey)] ??
        const <String>[];
  }

  String? _sessionPinnedHostForSite(String siteKey) {
    return _sessionPinnedHostBySite[_normalizeKnownSiteKey(siteKey)];
  }

  HostProbeSnapshot? _snapshotForSite(String siteKey) {
    return _snapshotsBySite[_normalizeKnownSiteKey(siteKey)];
  }

  static String siteLabel(String siteKey) {
    return switch (_normalizeSiteKey(siteKey)) {
      hotSiteKey => '热辣',
      _ => '拷贝',
    };
  }

  static Map<String, List<String>> _copyStringListMapWith(
    Map<String, List<String>> source,
    String siteKey,
    List<String> hosts,
  ) {
    return <String, List<String>>{
      ...source,
      siteKey: List<String>.unmodifiable(hosts),
    };
  }

  static Map<String, Map<String, List<String>>> _copyAliasMapWith(
    Map<String, Map<String, List<String>>> source,
    String siteKey,
    Map<String, List<String>> aliases,
  ) {
    return <String, Map<String, List<String>>>{
      ...source,
      siteKey: Map<String, List<String>>.unmodifiable(
        aliases.map(
          (String host, List<String> values) =>
              MapEntry(host, List<String>.unmodifiable(values)),
        ),
      ),
    };
  }

  static String _normalizeHost(String host) {
    return host.trim().toLowerCase();
  }

  static String _normalizeSiteKey(
    String? siteKey, {
    Iterable<String>? knownSiteKeys,
  }) {
    final String normalized = (siteKey ?? '').trim().toLowerCase();
    final String resolved = normalized.isEmpty ? copySiteKey : normalized;
    if (knownSiteKeys == null) {
      return resolved;
    }
    final Set<String> known = knownSiteKeys
        .map((String value) => value.trim().toLowerCase())
        .where((String value) => value.isNotEmpty)
        .toSet();
    if (known.isEmpty || known.contains(resolved)) {
      return resolved;
    }
    return known.contains(copySiteKey) ? copySiteKey : known.first;
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
    return _normalizeHost(input);
  }

  static bool _isValidHostName(String host) {
    final String normalizedHost = _normalizeHost(host);
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

  static Map<String, List<String>> _buildInitialCandidateHostsBySite({
    List<String>? candidateHosts,
    Map<String, List<String>>? candidateHostsBySite,
  }) {
    final Map<String, List<String>> hostsBySite = <String, List<String>>{};
    if (candidateHostsBySite != null) {
      for (final MapEntry<String, List<String>> entry
          in candidateHostsBySite.entries) {
        hostsBySite[_normalizeSiteKey(entry.key)] = entry.value;
      }
    }
    hostsBySite.putIfAbsent(
      copySiteKey,
      () => candidateHosts ?? _buildDefaultCandidateHosts(),
    );
    hostsBySite.putIfAbsent(hotSiteKey, _buildDefaultHotCandidateHosts);
    return _normalizeHostsBySite(hostsBySite);
  }

  static Map<String, List<String>> _normalizeHostsBySite(
    Map<String, List<String>> hostsBySite,
  ) {
    final Map<String, List<String>> normalized = <String, List<String>>{};
    for (final String siteKey in const <String>[copySiteKey, hotSiteKey]) {
      final List<String> hosts = _normalizeHosts(
        hostsBySite[siteKey] ?? const <String>[],
      );
      if (hosts.isNotEmpty) {
        normalized[siteKey] = hosts;
      }
    }
    for (final MapEntry<String, List<String>> entry in hostsBySite.entries) {
      final String siteKey = _normalizeSiteKey(entry.key);
      normalized.putIfAbsent(siteKey, () => _normalizeHosts(entry.value));
    }
    return normalized;
  }

  static Map<String, String> _firstHostsBySite(
    Map<String, List<String>> hostsBySite,
  ) {
    return <String, String>{
      for (final MapEntry<String, List<String>> entry in hostsBySite.entries)
        entry.key: _firstHost(entry.value),
    };
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

  static List<String> _buildDefaultHotCandidateHosts() {
    return _normalizeHosts(<String>['manga2026.com', 'www.manga2026.xyz']);
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

class _LoadedHostSnapshots {
  const _LoadedHostSnapshots({
    this.currentSiteKey = '',
    this.snapshots = const <String, HostProbeSnapshot>{},
  });

  final String currentSiteKey;
  final Map<String, HostProbeSnapshot> snapshots;
}
