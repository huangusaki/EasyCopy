part of '../site_api_client.dart';

class _SessionExpiredException extends SiteApiException {
  _SessionExpiredException() : super('登录已失效，请重新登录。');
}

class _SessionChangedException extends SiteApiException {
  _SessionChangedException() : super('登录状态已变化，请重试。');
}

extension _SiteApiSessionRecovery on SiteApiClient {
  void _checkSessionGeneration(int generation) {
    if (_session.generation != generation) throw _SessionChangedException();
  }

  Future<http.Response> _withSessionRecovery(
    Future<http.Response> Function() send,
  ) async {
    final int generation = _session.generation;
    final String? token = _session.token;
    final http.Response response = await send();
    _checkSessionGeneration(generation);
    if (!_isExpiredResponse(response)) return response;

    final bool recovered =
        token != null &&
        token.isNotEmpty &&
        await _recoverSession(generation, token);
    _checkSessionGeneration(generation);
    if (!recovered) throw _SessionExpiredException();

    final http.Response retried = await send();
    _checkSessionGeneration(generation);
    if (_isExpiredResponse(retried)) throw _SessionExpiredException();
    return retried;
  }

  bool _isExpiredResponse(http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) return true;
    if (response.statusCode < 200 || response.statusCode >= 300) return false;
    final Object? code = _tryDecodeJsonMap(response)?['code'];
    return code == 401 || code == 403;
  }

  Future<bool> _recoverSession(int generation, String token) {
    final recovery = _sessionRecovery;
    if (recovery != null &&
        recovery.generation == generation &&
        recovery.token == token) {
      return recovery.result;
    }
    // Another request may already have renewed this account's token.
    if (_session.token != token) {
      return Future<bool>.value(_session.isAuthenticated);
    }
    final Future<bool> result = _renewSession(generation, token);
    _sessionRecovery = (generation: generation, token: token, result: result);
    return result;
  }

  Future<bool> _renewSession(int generation, String token) async {
    try {
      final SavedLoginCredentials? credentials = await _credentialsStore.read();
      if (credentials == null || _session.generation != generation) {
        return false;
      }
      final String? username = _session.cookies['name'];
      if (username != null &&
          username.isNotEmpty &&
          username != credentials.username) {
        return false;
      }
      final String? userId = _session.userId ?? _session.cookies['user_id'];
      final SiteLoginResult result = await login(
        username: credentials.username,
        password: credentials.password,
      );
      final String? nextUserId = result.cookies['user_id'];
      if (userId != null && userId.isNotEmpty && nextUserId != userId) {
        return false;
      }
      return await _session.renewToken(
        result.token,
        cookies: result.cookies,
        expectedGeneration: generation,
        expiredToken: token,
      );
    } catch (_) {
      return false;
    }
  }
}
