import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:reader/services/android_document_tree_bridge.dart';

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

class TreeImageProvider extends ImageProvider<TreeImageProvider> {
  const TreeImageProvider({required this.treeUri, required this.relativePath});

  factory TreeImageProvider.fromUri(Uri uri) {
    final TreeImageRef reference = TreeImageRef.fromUri(uri);
    return TreeImageProvider(
      treeUri: reference.treeUri,
      relativePath: reference.relativePath,
    );
  }

  final String treeUri;
  final String relativePath;

  static final AndroidDocumentTreeBridge _bridge =
      AndroidDocumentTreeBridge.instance;

  @override
  Future<TreeImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<TreeImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    TreeImageProvider key,
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
    TreeImageProvider key,
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
    return other is TreeImageProvider &&
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
