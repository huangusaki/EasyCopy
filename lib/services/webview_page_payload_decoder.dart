import 'package:reader/models/page_models.dart';
import 'package:reader/services/page_cache_store.dart';
import 'package:reader/services/site_html_page_parser.dart';

class WebViewPagePayloadDecoder {
  WebViewPagePayloadDecoder._();

  static SitePage restore(Map<String, Object?> payload) {
    final Map<String, Object?> normalized = Map<String, Object?>.from(payload);
    _restoreReaderImages(normalized);
    _restoreDetailChapters(normalized);
    normalized.remove('readerCipherKey');
    normalized.remove('detailCipherKey');
    normalized.remove('detailChapterCiphertext');
    return PageCacheStore.restorePagePayload(normalized);
  }

  static void _restoreReaderImages(Map<String, Object?> payload) {
    if (payload['type'] != 'reader') {
      return;
    }

    final Uri? pageUri = Uri.tryParse((payload['uri'] as String?) ?? '');
    final String contentKey = (payload['contentKey'] as String?)?.trim() ?? '';
    final String cipherKey =
        (payload['readerCipherKey'] as String?)?.trim() ?? '';
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

  static void _restoreDetailChapters(Map<String, Object?> payload) {
    if (payload['type'] != 'detail') {
      return;
    }

    final Uri? pageUri = Uri.tryParse((payload['uri'] as String?) ?? '');
    final String ciphertext =
        (payload['detailChapterCiphertext'] as String?)?.trim() ?? '';
    final String cipherKey =
        (payload['detailCipherKey'] as String?)?.trim() ?? '';
    if (pageUri == null || ciphertext.isEmpty || cipherKey.isEmpty) {
      return;
    }
    final List<String> segments = pageUri.pathSegments;
    if (segments.length < 2 || segments.first != 'comic') {
      return;
    }

    try {
      final ParsedDetailChapters parsed = SiteHtmlPageParser.instance
          .parseEncryptedDetailChapters(
            pageUri: pageUri,
            slug: segments[1],
            ccz: cipherKey,
            encryptedResults: ciphertext,
          );
      // 章节列表由站点脚本异步渲染，DOM 抽取通常为空，因此解密结果优先。
      if (parsed.chapters.isEmpty) {
        return;
      }
      payload['chapterGroups'] = parsed.chapterGroups
          .map((ChapterGroupData group) => group.toJson())
          .toList();
      payload['chapters'] = parsed.chapters
          .map((ChapterData chapter) => chapter.toJson())
          .toList();
    } catch (_) {
      // 站点脚本变化或密文异常时，继续使用 WebView 当前 DOM 中的章节。
    }
  }
}
