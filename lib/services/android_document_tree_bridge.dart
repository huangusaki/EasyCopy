import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

@immutable
class PickedDocumentTreeDirectory {
  const PickedDocumentTreeDirectory({
    required this.treeUri,
    required this.displayName,
  });

  final String treeUri;
  final String displayName;

  factory PickedDocumentTreeDirectory.fromMap(Map<Object?, Object?> map) {
    return PickedDocumentTreeDirectory(
      treeUri: (map['treeUri'] as String?)?.trim() ?? '',
      displayName: (map['displayName'] as String?)?.trim() ?? '',
    );
  }
}

@immutable
class DocumentTreeDirectoryResolution {
  const DocumentTreeDirectoryResolution({
    required this.basePath,
    required this.rootPath,
    required this.isWritable,
    this.errorMessage = '',
  });

  final String basePath;
  final String rootPath;
  final bool isWritable;
  final String errorMessage;

  factory DocumentTreeDirectoryResolution.fromMap(Map<Object?, Object?> map) {
    return DocumentTreeDirectoryResolution(
      basePath: (map['basePath'] as String?)?.trim() ?? '',
      rootPath: (map['rootPath'] as String?)?.trim() ?? '',
      isWritable: (map['isWritable'] as bool?) ?? false,
      errorMessage: (map['errorMessage'] as String?)?.trim() ?? '',
    );
  }
}

@immutable
class DocumentTreeEntry {
  const DocumentTreeEntry({
    required this.relativePath,
    required this.name,
    required this.uri,
    required this.isDirectory,
    this.size = 0,
    this.lastModifiedMillis = 0,
  });

  final String relativePath;
  final String name;
  final String uri;
  final bool isDirectory;
  final int size;
  final int lastModifiedMillis;

  bool get isFile => !isDirectory;

  factory DocumentTreeEntry.fromMap(Map<Object?, Object?> map) {
    return DocumentTreeEntry(
      relativePath: (map['relativePath'] as String?)?.trim() ?? '',
      name: (map['name'] as String?)?.trim() ?? '',
      uri: (map['uri'] as String?)?.trim() ?? '',
      isDirectory: (map['isDirectory'] as bool?) ?? false,
      size: ((map['size'] as num?) ?? 0).round(),
      lastModifiedMillis: ((map['lastModifiedMillis'] as num?) ?? 0).round(),
    );
  }
}

@immutable
class DocumentTreeTransferProgress {
  const DocumentTreeTransferProgress({
    required this.completedCount,
    required this.totalCount,
    this.currentItemPath = '',
  });

  final int completedCount;
  final int totalCount;
  final String currentItemPath;

  factory DocumentTreeTransferProgress.fromMap(Map<Object?, Object?> map) {
    return DocumentTreeTransferProgress(
      completedCount: ((map['completedCount'] as num?) ?? 0).round(),
      totalCount: ((map['totalCount'] as num?) ?? 0).round(),
      currentItemPath: (map['currentItemPath'] as String?)?.trim() ?? '',
    );
  }
}

typedef DocumentTreeProgressCallback =
    FutureOr<void> Function(DocumentTreeTransferProgress progress);

class AndroidDocumentTreeBridge {
  AndroidDocumentTreeBridge({MethodChannel? methodChannel})
    : _methodChannel =
          methodChannel ??
          const MethodChannel('easy_copy/download_storage/methods') {
    _methodChannel.setMethodCallHandler(_handleMethodCall);
  }

  static final AndroidDocumentTreeBridge instance = AndroidDocumentTreeBridge();

  final MethodChannel _methodChannel;
  final Map<String, DocumentTreeProgressCallback> _progressCallbacks =
      <String, DocumentTreeProgressCallback>{};
  int _nextOperationId = 0;

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _handleMethodCall(MethodCall call) async {
    if (call.method != 'documentTreeProgress') {
      return;
    }
    final Map<Object?, Object?> rawArgs =
        (call.arguments as Map<Object?, Object?>?) ?? const <Object?, Object?>{};
    final String operationId = (rawArgs['operationId'] as String?)?.trim() ?? '';
    if (operationId.isEmpty) {
      return;
    }
    final DocumentTreeProgressCallback? callback =
        _progressCallbacks[operationId];
    if (callback == null) {
      return;
    }
    await callback(DocumentTreeTransferProgress.fromMap(rawArgs));
  }

  String _allocateOperationId() {
    _nextOperationId += 1;
    return '${DateTime.now().microsecondsSinceEpoch}_$_nextOperationId';
  }

  Future<PickedDocumentTreeDirectory?> pickDirectory() async {
    if (!isSupported) {
      return null;
    }
    final Map<Object?, Object?>? rawResult = await _methodChannel
        .invokeMapMethod<Object?, Object?>('pickDirectory');
    if (rawResult == null) {
      return null;
    }
    return PickedDocumentTreeDirectory.fromMap(rawResult);
  }

  Future<DocumentTreeDirectoryResolution> resolveDirectory({
    required String treeUri,
    String relativePath = '',
    bool verifyWritable = true,
  }) async {
    final Map<Object?, Object?>? rawResult = await _methodChannel
        .invokeMapMethod<Object?, Object?>(
          'resolveDirectory',
          <String, Object?>{
            'treeUri': treeUri,
            'relativePath': relativePath,
            'verifyWritable': verifyWritable,
          },
        );
    return DocumentTreeDirectoryResolution.fromMap(
      rawResult ?? const <Object?, Object?>{},
    );
  }

  Future<void> writeBytes({
    required String treeUri,
    required String relativePath,
    required Uint8List bytes,
  }) async {
    await _methodChannel.invokeMethod<void>('writeBytes', <String, Object?>{
      'treeUri': treeUri,
      'relativePath': relativePath,
      'bytes': bytes,
    });
  }

  Future<void> importDirectoryFromPath({
    required String treeUri,
    required String sourcePath,
    String relativePath = '',
    DocumentTreeProgressCallback? onProgress,
  }) async {
    final String? operationId = onProgress == null
        ? null
        : _allocateOperationId();
    if (operationId != null) {
      _progressCallbacks[operationId] = onProgress!;
    }
    try {
      await _methodChannel.invokeMethod<void>(
        'importDirectoryFromPath',
        <String, Object?>{
          'treeUri': treeUri,
          'sourcePath': sourcePath,
          'relativePath': relativePath,
          if (operationId != null) 'operationId': operationId,
        },
      );
    } finally {
      if (operationId != null) {
        _progressCallbacks.remove(operationId);
      }
    }
  }

  Future<void> exportDirectoryToPath({
    required String treeUri,
    required String destinationPath,
    String relativePath = '',
    DocumentTreeProgressCallback? onProgress,
  }) async {
    final String? operationId = onProgress == null
        ? null
        : _allocateOperationId();
    if (operationId != null) {
      _progressCallbacks[operationId] = onProgress!;
    }
    try {
      await _methodChannel.invokeMethod<void>(
        'exportDirectoryToPath',
        <String, Object?>{
          'treeUri': treeUri,
          'destinationPath': destinationPath,
          'relativePath': relativePath,
          if (operationId != null) 'operationId': operationId,
        },
      );
    } finally {
      if (operationId != null) {
        _progressCallbacks.remove(operationId);
      }
    }
  }

  Future<void> copyDirectoryToTree({
    required String sourceTreeUri,
    required String targetTreeUri,
    String sourceRelativePath = '',
    String targetRelativePath = '',
    DocumentTreeProgressCallback? onProgress,
  }) async {
    final String? operationId = onProgress == null
        ? null
        : _allocateOperationId();
    if (operationId != null) {
      _progressCallbacks[operationId] = onProgress!;
    }
    try {
      await _methodChannel.invokeMethod<void>(
        'copyDirectoryToTree',
        <String, Object?>{
          'sourceTreeUri': sourceTreeUri,
          'targetTreeUri': targetTreeUri,
          'sourceRelativePath': sourceRelativePath,
          'targetRelativePath': targetRelativePath,
          if (operationId != null) 'operationId': operationId,
        },
      );
    } finally {
      if (operationId != null) {
        _progressCallbacks.remove(operationId);
      }
    }
  }

  Future<void> writeText({
    required String treeUri,
    required String relativePath,
    required String text,
  }) async {
    await _methodChannel.invokeMethod<void>('writeText', <String, Object?>{
      'treeUri': treeUri,
      'relativePath': relativePath,
      'text': text,
    });
  }

  Future<String> readText({
    required String treeUri,
    required String relativePath,
  }) async {
    final String? rawText = await _methodChannel.invokeMethod<String>(
      'readText',
      <String, Object?>{'treeUri': treeUri, 'relativePath': relativePath},
    );
    return rawText ?? '';
  }

  Future<Uint8List> readBytes({
    required String treeUri,
    required String relativePath,
  }) async {
    final Uint8List? rawBytes = await _methodChannel.invokeMethod<Uint8List>(
      'readBytes',
      <String, Object?>{'treeUri': treeUri, 'relativePath': relativePath},
    );
    return rawBytes ?? Uint8List(0);
  }

  Future<Uint8List> readBytesFromUri(String documentUri) async {
    final Uint8List? rawBytes = await _methodChannel.invokeMethod<Uint8List>(
      'readBytesFromUri',
      <String, Object?>{'documentUri': documentUri},
    );
    return rawBytes ?? Uint8List(0);
  }

  Future<List<DocumentTreeEntry>> listEntries({
    required String treeUri,
    String relativePath = '',
    bool recursive = false,
  }) async {
    final List<Object?> rawEntries =
        await _methodChannel.invokeListMethod<Object?>(
          'listEntries',
          <String, Object?>{
            'treeUri': treeUri,
            'relativePath': relativePath,
            'recursive': recursive,
          },
        ) ??
        const <Object?>[];
    return rawEntries
        .whereType<Map<Object?, Object?>>()
        .map(DocumentTreeEntry.fromMap)
        .toList(growable: false);
  }

  Future<bool> exists({
    required String treeUri,
    required String relativePath,
  }) async {
    return await _methodChannel.invokeMethod<bool>('exists', <String, Object?>{
          'treeUri': treeUri,
          'relativePath': relativePath,
        }) ??
        false;
  }

  Future<bool> deletePath({
    required String treeUri,
    required String relativePath,
    DocumentTreeProgressCallback? onProgress,
  }) async {
    final String? operationId = onProgress == null
        ? null
        : _allocateOperationId();
    if (operationId != null) {
      _progressCallbacks[operationId] = onProgress!;
    }
    try {
      return await _methodChannel.invokeMethod<bool>(
            'deletePath',
            <String, Object?>{
              'treeUri': treeUri,
              'relativePath': relativePath,
              if (operationId != null) 'operationId': operationId,
            },
          ) ??
          false;
    } finally {
      if (operationId != null) {
        _progressCallbacks.remove(operationId);
      }
    }
  }
}
