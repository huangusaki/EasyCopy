import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:reader/services/android_document_tree_bridge.dart';
import 'package:reader/services/comic_download_service.dart';
import 'package:reader/services/local_comic.dart';
import 'package:reader/services/tree_image_provider.dart';

ImageProvider<Object>? localImageProvider(String url) {
  if (isLocalComic(url)) {
    return _LocalBytesImageProvider(
      url,
      () => ComicDownloadService.instance.loadLocalCoverBytes(url),
    );
  }
  final uri = Uri.tryParse(url);
  if (uri?.scheme == 'file') return FileImage(File.fromUri(uri!));
  if (uri?.scheme == 'content') {
    return _LocalBytesImageProvider(
      url,
      () => AndroidDocumentTreeBridge.instance.readBytesFromUri(url),
    );
  }
  if (uri?.scheme == treeImageScheme) {
    final ref = TreeImageRef.fromUri(uri!);
    final key = buildTreeImageUri(
      treeUri: ref.treeUri,
      relativePath: ref.relativePath,
    );
    return _LocalBytesImageProvider(
      key,
      () => AndroidDocumentTreeBridge.instance.readBytes(
        treeUri: ref.treeUri,
        relativePath: ref.relativePath,
      ),
    );
  }
  return null;
}

class _LocalBytesImageProvider extends ImageProvider<_LocalBytesImageProvider> {
  const _LocalBytesImageProvider(this.uri, this.readBytes);

  final String uri;
  final Future<Uint8List> Function() readBytes;

  @override
  Future<_LocalBytesImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) => SynchronousFuture<_LocalBytesImageProvider>(this);

  @override
  ImageStreamCompleter loadImage(
    _LocalBytesImageProvider key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _loadImage(decode),
    scale: 1,
    debugLabel: uri,
  );

  Future<ui.Codec> _loadImage(ImageDecoderCallback decode) async {
    final bytes = await readBytes();
    if (bytes.isEmpty) throw StateError('本地图片为空：$uri');
    return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
  }

  @override
  bool operator ==(Object other) =>
      other is _LocalBytesImageProvider && other.uri == uri;

  @override
  int get hashCode => uri.hashCode;
}
