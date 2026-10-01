import 'package:html/parser.dart' as html_parser;
import 'package:path_provider/path_provider.dart';
import 'package:reader/services/debug_trace.dart';
import 'package:reader/services/persistence/atomic_json_file.dart';

class SearchEndpointUnavailable implements Exception {
  const SearchEndpointUnavailable();
}

/// Reads the endpoint published by the site and persists verified responses.
class SearchEndpointResolver {
  SearchEndpointResolver({JsonDirectoryProvider? directoryProvider})
    : _file = AtomicJsonFile<Map<String, String>>(
        directoryProvider: directoryProvider ?? getApplicationSupportDirectory,
        relativePath: 'search_endpoints.json',
        decode: (Object? json) => Map<String, String>.from(json as Map)
          ..removeWhere((_, suffix) => !RegExp(r'^[a-z]$').hasMatch(suffix)),
        encode: (value) => value,
      );

  static final SearchEndpointResolver instance = SearchEndpointResolver();
  static final RegExp _endpointDeclaration = RegExp(
    r'''\b(?:const|let|var)\s+countApi\s*=\s*(['"])/api/kb/web/searchc([a-z])/comics\1''',
  );

  final AtomicJsonFile<Map<String, String>> _file;
  final Map<String, Future<String>> _refreshes = <String, Future<String>>{};
  final Map<String, String> _suffixes = <String, String>{};
  Map<String, String> _persisted = <String, String>{};
  Future<void>? _initialization;

  Future<void> _initialize() async {
    try {
      _persisted = await _file.read() ?? <String, String>{};
      _suffixes.addAll(_persisted);
    } catch (_) {
      // The endpoint can still be discovered if local storage is unavailable.
    }
  }

  Future<String?> suffixFor(String host) async {
    await (_initialization ??= _initialize());
    return _suffixes[host];
  }

  Future<void> confirm(String host, String suffix) async {
    // A slow successful response must not overwrite a newer discovery.
    if (await suffixFor(host) != suffix) return;
    if (_persisted[host] == suffix) return;
    try {
      await _file.update(
        (current) => <String, String>{...?current, host: suffix},
      );
      _persisted[host] = suffix;
    } catch (error) {
      DebugTrace.log('search.endpoint_persist_failed', <String, Object?>{
        'host': host,
        'error': error.toString(),
      });
    }
  }

  Future<String> refresh({
    required String host,
    required String? previousSuffix,
    required Future<String> Function() loadPage,
  }) async {
    final String? current = await suffixFor(host);
    final Future<String>? pending = _refreshes[host];
    if (pending != null) return pending;
    // Another search may have already replaced the endpoint that just failed.
    if (current != null && current != previousSuffix) return current;

    final Future<String> refresh = _readEndpoint(host, loadPage);
    _refreshes[host] = refresh;
    try {
      return await refresh;
    } finally {
      _refreshes.removeWhere((key, _) => key == host);
    }
  }

  Future<String> _readEndpoint(
    String host,
    Future<String> Function() loadPage,
  ) async {
    final document = html_parser.parse(await loadPage());
    for (final script in document.querySelectorAll('script:not([src])')) {
      final RegExpMatch? match = _endpointDeclaration.firstMatch(script.text);
      if (match != null) {
        final String suffix = match.group(2)!;
        _suffixes[host] = suffix;
        return suffix;
      }
    }
    throw const SearchEndpointUnavailable();
  }
}
