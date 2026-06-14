import 'package:reader/config/app_config.dart';

/// 站点 href/URI 的稳定 key 归一化。
///
/// [pathKey] 用于内存态匹配；[rawPathKey] 用于持久化主键，不能改口径。
class UriKeys {
  const UriKeys._();

  static String pathKey(String href) {
    final Uri? uri = Uri.tryParse(href);
    if (uri == null) {
      return '';
    }
    return Uri(path: AppConfig.rewriteToCurrentHost(uri).path).toString();
  }

  static String rawPathKey(String href) {
    final Uri? uri = Uri.tryParse(href.trim());
    if (uri == null) {
      return '';
    }
    return uri.path.trim();
  }
}
