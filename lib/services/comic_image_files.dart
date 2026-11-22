const comicImageExtensions = <String>{
  'jpg',
  'jpeg',
  'png',
  'webp',
  'gif',
  'bmp',
  'avif',
};

String cleanComicPathSegment(String title) => title
    .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .replaceAll(RegExp(r'[. ]+$'), '');
