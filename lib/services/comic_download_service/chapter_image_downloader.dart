import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:reader/services/comic_download_service/download_contracts.dart';
import 'package:reader/services/network_client.dart';
import 'package:reader/services/quic_http_client.dart';

/// Bounded image transfer; the caller owns paths, manifests and library indexes.
class ChapterImageDownloader {
  ChapterImageDownloader({http.Client? client, this.concurrency = 3})
    : assert(concurrency > 0),
      _client = client ?? AppHttpClientFactory.create();

  final http.Client _client;
  final int concurrency;

  Future<List<String>> download({
    required List<String> imageUrls,
    required Map<String, String> headers,
    required Map<int, String> existingFiles,
    required Future<void> Function(String fileName, Uint8List bytes) writeImage,
    ChapterDownloadProgressCallback? onProgress,
    ChapterDownloadPauseChecker? shouldPause,
    ChapterDownloadCancelChecker? shouldCancel,
  }) async {
    final List<String> files = List<String>.filled(imageUrls.length, '');
    for (final MapEntry<int, String> file in existingFiles.entries) {
      if (file.key >= 0 && file.key < files.length) {
        files[file.key] = file.value;
      }
    }
    int completed = files.where((file) => file.isNotEmpty).length;
    int next = 0;
    Object? failure;
    StackTrace? failureStack;

    void checkControl() {
      if (shouldCancel?.call() == true) {
        throw const DownloadCancelledException();
      }
      if (shouldPause?.call() == true) throw const DownloadPausedException();
    }

    Future<void> worker() async {
      try {
        while (failure == null) {
          checkControl();
          final int index = next++;
          if (index >= files.length) return;
          final bool restored = files[index].isNotEmpty;
          if (!restored) {
            final Uri uri = Uri.parse(imageUrls[index]);
            final http.Response response = await NetworkClient.get(
              _client,
              uri,
              headers: headers,
              timeout: NetworkClient.imageTimeout,
              maxRetries: 2,
              label: 'download.image',
            );
            checkControl();
            if (failure != null) return;
            if (response.statusCode < 200 || response.statusCode >= 300) {
              throw HttpException(
                'Image download failed: ${response.statusCode}',
                uri: uri,
              );
            }
            final String extension = _extension(
              uri,
              response.headers['content-type'],
            );
            final String fileName =
                '${(index + 1).toString().padLeft(3, '0')}.$extension';
            await writeImage(fileName, response.bodyBytes);
            checkControl();
            files[index] = fileName;
            completed += 1;
          }
          if (failure != null) return;
          await onProgress?.call(
            ChapterDownloadProgress(
              completedCount: completed,
              totalCount: files.length,
              currentLabel:
                  '${restored ? '已恢复' : '已缓存'} $completed/${files.length}',
            ),
          );
        }
      } catch (error, stack) {
        failure ??= error;
        failureStack ??= stack;
      }
    }

    await Future.wait(<Future<void>>[
      for (int index = 0; index < concurrency && index < files.length; index++)
        worker(),
    ]);
    if (failure != null) Error.throwWithStackTrace(failure!, failureStack!);
    checkControl();
    return files;
  }

  String _extension(Uri uri, String? contentType) {
    final RegExpMatch? match = RegExp(
      r'\.(avif|bmp|gif|jpeg|jpg|png|webp)$',
      caseSensitive: false,
    ).firstMatch(uri.path);
    if (match != null) return match.group(1)!.toLowerCase();
    final String type = (contentType ?? '').toLowerCase();
    for (final String extension in const <String>[
      'png',
      'webp',
      'gif',
      'bmp',
      'avif',
    ]) {
      if (type.contains(extension)) return extension;
    }
    return 'jpg';
  }
}
