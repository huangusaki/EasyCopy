import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:reader/services/android_document_tree_bridge.dart';

class DocumentTreeImageProvider
    extends ImageProvider<DocumentTreeImageProvider> {
  const DocumentTreeImageProvider(this.documentUri);

  final String documentUri;

  static final AndroidDocumentTreeBridge _bridge =
      AndroidDocumentTreeBridge.instance;

  @override
  Future<DocumentTreeImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) {
    return SynchronousFuture<DocumentTreeImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    DocumentTreeImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
      debugLabel: documentUri,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<String>('Document URI', documentUri),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(
    DocumentTreeImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    assert(key == this);
    final Uint8List bytes = await _bridge.readBytesFromUri(documentUri);
    if (bytes.isEmpty) {
      throw StateError('Document image is empty: $documentUri');
    }
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
      bytes,
    );
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) {
    return other is DocumentTreeImageProvider &&
        other.documentUri == documentUri;
  }

  @override
  int get hashCode => documentUri.hashCode;

  @override
  String toString() => '$runtimeType("$documentUri")';
}
