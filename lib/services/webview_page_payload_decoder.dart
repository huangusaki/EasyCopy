import 'package:reader/config/app_config.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/services/page_cache_store.dart';
import 'package:reader/services/site_html_page_parser.dart';

class WebViewPagePayloadDecoder {
  WebViewPagePayloadDecoder._();

  static Future<SitePage> restore(Map<String, Object?> payload) async {
    _restoreReaderImages(payload);
    payload.remove('readerCipherKey');
    final chapters = await _restoreDetailChapters(payload);
    if (chapters != null && chapters.chapters.isNotEmpty) {
      payload.remove('chapterGroups');
      payload.remove('chapters');
      final detail =
          PageCacheStore.restorePagePayload(payload) as DetailPageData;
      return detail.copyWith(
        chapterGroups: chapters.chapterGroups,
        chapters: chapters.chapters,
      );
    }
    return PageCacheStore.restorePagePayload(payload);
  }

  static void _restoreReaderImages(Map<String, Object?> payload) {
    if (payload['type'] != 'reader') {
      return;
    }

    final Uri? pageUri = Uri.tryParse((payload['uri'] as String?) ?? '');
    final String contentKey = (payload['contentKey'] as String?)?.trim() ?? '';
    final String cipherKey =
        (payload['readerCipherKey'] as String?)?.trim() ?? '';
    if ((payload['chapterTitle'] as String? ?? '').trim().isNotEmpty ||
        (payload['progressLabel'] as String? ?? '').trim().isNotEmpty ||
        (pageUri?.pathSegments.isNotEmpty ?? false)) {
      payload.remove('contentKey');
    }
    if (pageUri == null || contentKey.isEmpty || cipherKey.isEmpty) {
      return;
    }

    try {
      final List<String> decrypted = SiteHtmlPageParser.instance
          .parseEncryptedReaderImageUrls(
            pageUri,
            contentKey: contentKey,
            cct: cipherKey,
          );
      // 与 Dart/Android 解析口径保持一致：解密结果优先，仅在其为空时才回退
      // DOM 抽取值。若改成「严格更长才采用」，懒加载渲染出等量占位图时
      // (decrypted.length == extractedCount) 占位图会胜出，导致 Windows 整章裂图。
      if (decrypted.isNotEmpty) {
        payload['imageUrls'] = decrypted;
      }
    } catch (_) {
      // 站点脚本变化或密文异常时，继续使用 WebView 当前 DOM 中的图片。
    }
  }

  static Future<ParsedDetailChapters?> _restoreDetailChapters(
    Map<String, Object?> payload,
  ) async {
    final ciphertext =
        (payload.remove('detailChapterCiphertext') as String?)?.trim() ?? '';
    final cipherKey =
        (payload.remove('detailCipherKey') as String?)?.trim() ?? '';
    if (payload['type'] != 'detail' ||
        ciphertext.isEmpty ||
        cipherKey.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(payload['uri'] as String? ?? '');
    if (uri == null ||
        uri.pathSegments.length < 2 ||
        uri.pathSegments.first != 'comic') {
      return null;
    }

    try {
      return await SiteHtmlPageParser.instance
          .parseEncryptedDetailChaptersAsync(
            pageUri: AppConfig.rewriteToCurrentHost(uri),
            slug: uri.pathSegments[1],
            ccz: cipherKey,
            encryptedResults: ciphertext,
          );
    } catch (_) {
      // 密文异常时保留 DOM 提取到的章节。
      return null;
    }
  }
}
