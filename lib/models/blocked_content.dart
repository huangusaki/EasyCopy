import 'package:flutter/foundation.dart';

enum BlockedContentType { comic, author }

@immutable
class BlockedContentItem {
  const BlockedContentItem({
    required this.type,
    required this.key,
    required this.label,
    this.href = '',
    this.addedAtMs = 0,
  });

  factory BlockedContentItem.fromJson(Map<String, Object?> json) {
    return BlockedContentItem(
      type: BlockedContentType.values.firstWhere(
        (BlockedContentType value) => value.name == json['type'],
        orElse: () => BlockedContentType.comic,
      ),
      key: (json['key'] as String?) ?? '',
      label: (json['label'] as String?) ?? '',
      href: (json['href'] as String?) ?? '',
      addedAtMs: (json['addedAtMs'] as num?)?.toInt() ?? 0,
    );
  }

  final BlockedContentType type;
  final String key;
  final String label;
  final String href;
  final int addedAtMs;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'type': type.name,
      'key': key,
      'label': label,
      'href': href,
      'addedAtMs': addedAtMs,
    };
  }
}
