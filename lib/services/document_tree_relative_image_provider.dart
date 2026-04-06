import 'dart:async';
import 'dart:ui' as ui;

import 'package:easy_copy/services/android_document_tree_bridge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

const String documentTreeRelativeImageScheme = 'easycopy-document-tree';

String buildDocumentTreeRelativeImageUri({
  required String treeUri,
  required String relativePath,
}) {
  return Uri(
    scheme: documentTreeRelativeImageScheme,
    queryParameters: <String, String>{
      'treeUri': treeUri,
      'relativePath': relativePath,
    },
  ).toString();
}

@immutable
class DocumentTreeRelativeImageReference {
  const DocumentTreeRelativeImageReference({
    required this.treeUri,
    required this.relativePath,
  });

  factory DocumentTreeRelativeImageReference.fromUri(Uri uri) {
    if (uri.scheme != documentTreeRelativeImageScheme) {
      throw ArgumentError.value(
        uri.toString(),
        'uri',
        'Unsupported document tree image scheme.',
      );
    }
    return DocumentTreeRelativeImageReference(
      treeUri: uri.queryParameters['treeUri']?.trim() ?? '',
      relativePath: uri.queryParameters['relativePath']?.trim() ?? '',
    );
  }

  final String treeUri;
  final String relativePath;
}

class DocumentTreeRelativeImageProvider
    extends ImageProvider<DocumentTreeRelativeImageProvider> {
  const DocumentTreeRelativeImageProvider({
    required this.treeUri,
    required this.relativePath,
  });

  factory DocumentTreeRelativeImageProvider.fromUri(Uri uri) {
    final DocumentTreeRelativeImageReference reference =
        DocumentTreeRelativeImageReference.fromUri(uri);
    return DocumentTreeRelativeImageProvider(
      treeUri: reference.treeUri,
      relativePath: reference.relativePath,
    );
  }

  final String treeUri;
  final String relativePath;

  static final AndroidDocumentTreeBridge _bridge =
      AndroidDocumentTreeBridge.instance;

  @override
  Future<DocumentTreeRelativeImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) {
    return SynchronousFuture<DocumentTreeRelativeImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    DocumentTreeRelativeImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1.0,
      debugLabel: '$treeUri::$relativePath',
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<String>('Tree URI', treeUri),
        DiagnosticsProperty<String>('Relative path', relativePath),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(
    DocumentTreeRelativeImageProvider key,
    ImageDecoderCallback decode,
  ) async {
    assert(key == this);
    final Uint8List bytes = await _bridge.readBytes(
      treeUri: treeUri,
      relativePath: relativePath,
    );
    if (bytes.isEmpty) {
      throw StateError('Document tree image is empty: $treeUri::$relativePath');
    }
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(
      bytes,
    );
    return decode(buffer);
  }

  @override
  bool operator ==(Object other) {
    return other is DocumentTreeRelativeImageProvider &&
        other.treeUri == treeUri &&
        other.relativePath == relativePath;
  }

  @override
  int get hashCode => Object.hash(treeUri, relativePath);

  @override
  String toString() {
    return '$runtimeType(treeUri: "$treeUri", relativePath: "$relativePath")';
  }
}
