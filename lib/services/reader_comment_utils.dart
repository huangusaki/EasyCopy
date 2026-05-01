import 'dart:collection';
import 'dart:math' as math;

import 'package:easy_copy/models/chapter_comment.dart';
import 'package:flutter/foundation.dart';

const int readerCommentPageSize = 40;

@immutable
class ReaderCommentPageWindow {
  const ReaderCommentPageWindow({required this.offset, required this.limit});

  static const ReaderCommentPageWindow empty = ReaderCommentPageWindow(
    offset: 0,
    limit: 0,
  );

  final int offset;
  final int limit;

  bool get isEmpty => limit <= 0;
}

ReaderCommentPageWindow initialReaderCommentAscendingWindow({
  required int total,
  int pageSize = readerCommentPageSize,
}) {
  if (total <= 0 || pageSize <= 0) {
    return ReaderCommentPageWindow.empty;
  }
  final int limit = math.min(total, pageSize);
  return ReaderCommentPageWindow(
    offset: math.max(0, total - limit),
    limit: limit,
  );
}

ReaderCommentPageWindow nextReaderCommentAscendingWindow({
  required int loadedStartOffset,
  int pageSize = readerCommentPageSize,
}) {
  if (loadedStartOffset <= 0 || pageSize <= 0) {
    return ReaderCommentPageWindow.empty;
  }
  final int nextStartOffset = math.max(0, loadedStartOffset - pageSize);
  return ReaderCommentPageWindow(
    offset: nextStartOffset,
    limit: loadedStartOffset - nextStartOffset,
  );
}

List<ChapterComment> normalizeReaderCommentAscendingPage(
  List<ChapterComment> comments,
) {
  return List<ChapterComment>.unmodifiable(comments.reversed);
}

List<ChapterComment> mergeReaderCommentsByIdentity(
  List<ChapterComment> existing,
  List<ChapterComment> incoming,
) {
  final Set<String> seen = <String>{};
  final List<ChapterComment> merged = <ChapterComment>[];
  for (final ChapterComment comment in <ChapterComment>[
    ...existing,
    ...incoming,
  ]) {
    final String identity = comment.id.isNotEmpty
        ? comment.id
        : '${comment.avatarUrl}\n${comment.message}';
    if (!seen.add(identity)) {
      continue;
    }
    merged.add(comment);
  }
  return List<ChapterComment>.unmodifiable(merged);
}

@immutable
class ReaderCommentCluster {
  const ReaderCommentCluster({
    required this.message,
    required this.avatarUrls,
    required this.count,
  });

  final String message;
  final List<String> avatarUrls;
  final int count;

  bool get hasOverflowAvatars => count > 3;
}

List<ReaderCommentCluster> buildReaderCommentClusters(
  List<ChapterComment> comments,
) {
  final LinkedHashMap<String, List<ChapterComment>> grouped =
      LinkedHashMap<String, List<ChapterComment>>();
  for (final ChapterComment comment in comments) {
    final String message = comment.message.trim();
    if (message.isEmpty) {
      continue;
    }
    grouped.putIfAbsent(message, () => <ChapterComment>[]).add(comment);
  }

  return List<ReaderCommentCluster>.unmodifiable(
    grouped.entries.map((MapEntry<String, List<ChapterComment>> entry) {
      return ReaderCommentCluster(
        message: entry.key,
        avatarUrls: List<String>.unmodifiable(
          entry.value.map((ChapterComment comment) => comment.avatarUrl),
        ),
        count: entry.value.length,
      );
    }),
  );
}
