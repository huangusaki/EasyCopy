import 'package:flutter/foundation.dart';

@immutable
class ChapterComment {
  const ChapterComment({
    required this.id,
    required this.message,
    this.avatarUrl = '',
  });

  final String id;
  final String message;
  final String avatarUrl;
}

@immutable
class ChapterCommentFeed {
  const ChapterCommentFeed({
    this.total = 0,
    this.comments = const <ChapterComment>[],
  });

  final int total;
  final List<ChapterComment> comments;
}
