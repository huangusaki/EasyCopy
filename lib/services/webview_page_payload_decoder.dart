import 'package:reader/models/page_models.dart';
import 'package:reader/services/page_cache_store.dart';
import 'package:reader/services/site_html_page_parser.dart';

class WebViewPagePayloadDecoder {
  WebViewPagePayloadDecoder._();

  static SitePage restore(Map<String, Object?> payload) {
    final Map<String, Object?> normalized = Map<String, Object?>.from(payload);
    _restoreReaderImages(normalized);
    normalized.remove('readerCipherKey');
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
      final int extractedCount = (payload['imageUrls'] as List?)?.length ?? 0;
      if (decrypted.length > extractedCount) {
        payload['imageUrls'] = decrypted;
      }
    } catch (_) {
      // 站点脚本变化或密文异常时，继续使用 WebView 当前 DOM 中的图片。
    }
  }
}
