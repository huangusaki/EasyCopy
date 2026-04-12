import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AppUpdateCheckException implements Exception {
  AppUpdateCheckException(this.message);

  final String message;

  @override
  String toString() => message;
}

@immutable
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseUri,
    required this.hasUpdate,
  });

  final String currentVersion;
  final String latestVersion;
  final Uri releaseUri;
  final bool hasUpdate;
}

class AppUpdateChecker {
  AppUpdateChecker({http.Client? client}) : _client = client ?? http.Client();

  static final AppUpdateChecker instance = AppUpdateChecker();
  static final Uri repositoryUri = Uri.parse(
    'https://github.com/huangusaki/EasyCopy',
  );
  static final Uri releasesUri = Uri.parse(
    'https://github.com/huangusaki/EasyCopy/releases',
  );
  static final Uri _latestReleaseApiUri = Uri.parse(
    'https://api.github.com/repos/huangusaki/EasyCopy/releases/latest',
  );

  final http.Client _client;

  Future<AppUpdateInfo> checkForUpdates({
    required String currentVersion,
  }) async {
    final String normalizedCurrentVersion = normalizeVersionTag(currentVersion);
    if (normalizedCurrentVersion.isEmpty) {
      throw AppUpdateCheckException('当前版本不可用');
    }

    final http.Response response = await _client.get(
      _latestReleaseApiUri,
      headers: const <String, String>{
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'EasyCopy',
      },
    );
    if (response.statusCode >= 400) {
      throw AppUpdateCheckException('更新检查失败：${response.statusCode}');
    }

    final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw AppUpdateCheckException('更新信息格式异常');
    }
    final Map<String, Object?> payload = decoded.map(
      (Object? key, Object? value) => MapEntry(key.toString(), value),
    );
    final String latestVersion = normalizeVersionTag(
      (payload['tag_name'] as String?) ?? '',
    );
    if (latestVersion.isEmpty) {
      throw AppUpdateCheckException('未找到可用版本');
    }

    final String htmlUrl = (payload['html_url'] as String?)?.trim() ?? '';
    final Uri releaseUri = Uri.tryParse(htmlUrl) ?? releasesUri;
    return AppUpdateInfo(
      currentVersion: normalizedCurrentVersion,
      latestVersion: latestVersion,
      releaseUri: releaseUri,
      hasUpdate:
          compareSemanticVersions(normalizedCurrentVersion, latestVersion) < 0,
    );
  }
}

@visibleForTesting
String normalizeVersionTag(String value) {
  final String trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  final Match? match = RegExp(r'(\d+(?:\.\d+)*)').firstMatch(trimmed);
  return match?.group(1) ?? '';
}

@visibleForTesting
int compareSemanticVersions(String left, String right) {
  final List<int> leftParts = _parseVersionParts(left);
  final List<int> rightParts = _parseVersionParts(right);
  final int maxLength = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;
  for (int index = 0; index < maxLength; index += 1) {
    final int leftValue = index < leftParts.length ? leftParts[index] : 0;
    final int rightValue = index < rightParts.length ? rightParts[index] : 0;
    if (leftValue != rightValue) {
      return leftValue.compareTo(rightValue);
    }
  }
  return 0;
}

List<int> _parseVersionParts(String value) {
  final String normalized = normalizeVersionTag(value);
  if (normalized.isEmpty) {
    return const <int>[0];
  }
  return normalized
      .split('.')
      .map((String part) => int.tryParse(part) ?? 0)
      .toList(growable: false);
}
