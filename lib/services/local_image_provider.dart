import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:reader/services/comic_download_service.dart';
import 'package:reader/services/document_tree_image_provider.dart';
import 'package:reader/services/local_comic.dart';
import 'package:reader/services/tree_image_provider.dart';

ImageProvider<Object>? localImageProvider(String url) {
  if (isLocalComic(url)) return LocalComicCoverProvider(url);
  final Uri? uri = Uri.tryParse(url);
  return switch (uri?.scheme) {
    'file' => FileImage(File.fromUri(uri!)),
    treeImageScheme => TreeImageProvider.fromUri(uri!),
    'content' => DocumentTreeImageProvider(url),
    _ => null,
  };
}

class LocalComicCoverProvider extends ImageProvider<LocalComicCoverProvider> {
  const LocalComicCoverProvider(this.uri);

  final String uri;

  @override
  Future<LocalComicCoverProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<LocalComicCoverProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    LocalComicCoverProvider key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _loadImage(decode),
    scale: 1,
    debugLabel: uri,
  );

  Future<ui.Codec> _loadImage(ImageDecoderCallback decode) async {
    final bytes = await ComicDownloadService.instance.loadLocalCoverBytes(uri);
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is LocalComicCoverProvider && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;
}
