bool isLocalComic(String value) {
  final Uri? uri = Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'local' &&
      uri.host.isEmpty &&
      uri.pathSegments.length >= 2 &&
      uri.pathSegments.first == 'comic' &&
      uri.pathSegments[1].isNotEmpty;
}

String localComicUri(String id) => 'local:///comic/${Uri.encodeComponent(id)}';

String localChapterUri(String id, int index) =>
    '${localComicUri(id)}/chapter/${index.toString().padLeft(3, '0')}';
