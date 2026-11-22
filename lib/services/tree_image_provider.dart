import 'package:flutter/foundation.dart';

const String treeImageScheme = 'easycopy-document-tree';

String buildTreeImageUri({
  required String treeUri,
  required String relativePath,
}) {
  return Uri(
    scheme: treeImageScheme,
    queryParameters: <String, String>{
      'treeUri': treeUri,
      'relativePath': relativePath,
    },
  ).toString();
}

@immutable
class TreeImageRef {
  const TreeImageRef({required this.treeUri, required this.relativePath});

  factory TreeImageRef.fromUri(Uri uri) {
    if (uri.scheme != treeImageScheme) {
      throw ArgumentError.value(
        uri.toString(),
        'uri',
        'Unsupported document tree image scheme.',
      );
    }
    return TreeImageRef(
      treeUri: uri.queryParameters['treeUri']?.trim() ?? '',
      relativePath: uri.queryParameters['relativePath']?.trim() ?? '',
    );
  }

  final String treeUri;
  final String relativePath;
}
