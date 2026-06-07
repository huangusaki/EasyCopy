import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:reader/models/app_preferences.dart';
import 'package:reader/models/chapter_comment.dart';
import 'package:reader/models/page_models.dart';
import 'package:reader/services/reader_comment_utils.dart';
import 'package:reader/services/site_api_client.dart';
import 'package:reader/services/site_session.dart';

class ReaderCommentsController {
  ReaderCommentsController({
    required this.apiClient,
    required this.session,
    required this.preferences,
    required this.currentPage,
    required this.chapterIdForPage,
    required this.isDisposed,
    required this.notify,
    required this.onRequestAuth,
    required this.onLogoutForExpiredSession,
    required this.onShowMessage,
  });

  final SiteApiClient apiClient;
  final SiteSession session;
  final ReaderPreferences Function() preferences;
  final ReaderPageData? Function() currentPage;
  final String Function(ReaderPageData page) chapterIdForPage;
  final bool Function() isDisposed;
  final VoidCallback notify;
  final Future<void> Function() onRequestAuth;
  final Future<void> Function() onLogoutForExpiredSession;
  final void Function(String message) onShowMessage;

  final TextEditingController textController = TextEditingController();
  final ScrollController scrollController = ScrollController();

  List<ChapterComment> _items = const <ChapterComment>[];
  String _chapterId = '';
  String _error = '';
  int _total = 0;
  int _loadedStartOffset = 0;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _isSubmitting = false;

  List<ChapterComment> get items => _items;
  String get chapterId => _chapterId;
  String get error => _error;
  int get total => _total;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get isSubmitting => _isSubmitting;

  bool shouldShowTailPage(ReaderPageData page) {
    return preferences().showChapterComments &&
        chapterIdForPage(page).isNotEmpty;
  }

  void prepare(ReaderPageData page, {required bool resetForNewChapter}) {
    final String nextChapterId = chapterIdForPage(page);
    if (!preferences().showChapterComments || nextChapterId.isEmpty) {
      _chapterId = '';
      _error = '';
      _items = const <ChapterComment>[];
      _total = 0;
      _loadedStartOffset = 0;
      _isLoading = false;
      _isLoadingMore = false;
      if (resetForNewChapter) {
        textController.clear();
      }
      _notify();
      return;
    }

    final bool shouldRefresh =
        resetForNewChapter ||
        _chapterId != nextChapterId ||
        (_items.isEmpty && _error.isEmpty);
    if (!shouldRefresh || (_isLoading && _chapterId == nextChapterId)) {
      return;
    }
    if (resetForNewChapter) {
      textController.clear();
      if (scrollController.hasClients) {
        scrollController.jumpTo(0);
      }
    }
    unawaited(load(page));
  }

  Future<void> load(ReaderPageData page, {bool append = false}) async {
    final String nextChapterId = chapterIdForPage(page);
    if (nextChapterId.isEmpty || !preferences().showChapterComments) {
      return;
    }
    if (!isDisposed()) {
      final ReaderPageData? current = currentPage();
      if (current == null || chapterIdForPage(current) != nextChapterId) {
        return;
      }
    }

    final List<ChapterComment> existingComments =
        append && _chapterId == nextChapterId
        ? _items
        : const <ChapterComment>[];
    ReaderCommentPageWindow? appendWindow;
    if (append) {
      if (_isLoading || _isLoadingMore) return;
      appendWindow = nextCommentWindow(loadedStartOffset: _loadedStartOffset);
      if (appendWindow.isEmpty) return;
    }

    if (!append) {
      _chapterId = nextChapterId;
      _error = '';
      _items = const <ChapterComment>[];
      _total = 0;
      _loadedStartOffset = 0;
      _isLoading = true;
      _isLoadingMore = false;
      _notify();
    } else {
      _isLoadingMore = true;
      _notify();
    }

    try {
      final (
        ChapterCommentFeed feed,
        int loadedStartOffset,
        int resolvedTotal,
      ) = append
          ? await _loadAscendingPage(
              chapterId: nextChapterId,
              window: appendWindow!,
              fallbackTotal: _total,
            )
          : await _loadInitialPage(nextChapterId);
      if (isDisposed()) return;
      final ReaderPageData? current = currentPage();
      if (current == null || chapterIdForPage(current) != nextChapterId) {
        _clearLoadingIfCurrent(nextChapterId);
        return;
      }
      _chapterId = nextChapterId;
      _items = append
          ? mergeReaderCommentsByIdentity(existingComments, feed.comments)
          : mergeReaderCommentsByIdentity(
              const <ChapterComment>[],
              feed.comments,
            );
      _total = resolvedTotal > 0 ? resolvedTotal : _items.length;
      _loadedStartOffset = loadedStartOffset;
      _error = '';
      _isLoading = false;
      _isLoadingMore = false;
      _notify();
    } catch (error) {
      if (isDisposed()) return;
      final ReaderPageData? current = currentPage();
      if (current == null || chapterIdForPage(current) != nextChapterId) {
        _clearLoadingIfCurrent(nextChapterId);
        return;
      }
      final String message = error is SiteApiException
          ? error.message
          : '评论加载失败，请稍后重试。';
      if (append && existingComments.isNotEmpty) {
        _isLoading = false;
        _isLoadingMore = false;
        _notify();
        return;
      }
      _chapterId = nextChapterId;
      _error = message;
      _items = const <ChapterComment>[];
      _total = 0;
      _loadedStartOffset = 0;
      _isLoading = false;
      _isLoadingMore = false;
      _notify();
    }
  }

  void handleScroll() {
    if (!scrollController.hasClients || _isLoading || _isLoadingMore) {
      return;
    }
    final ReaderPageData? current = currentPage();
    if (current == null || !shouldShowTailPage(current)) {
      return;
    }
    final ScrollPosition position = scrollController.position;
    if (position.maxScrollExtent <= 0) return;
    if (position.maxScrollExtent - position.pixels > 180) return;
    unawaited(load(current, append: true));
  }

  Future<void> submit(ReaderPageData page) async {
    if (_isSubmitting) return;
    final String nextChapterId = chapterIdForPage(page);
    if (nextChapterId.isEmpty) {
      onShowMessage('章节评论信息缺失，请刷新后重试。');
      return;
    }
    final String content = textController.text.trim();
    if (content.isEmpty) {
      onShowMessage('请输入评论内容。');
      return;
    }

    if (!session.isAuthenticated || (session.token ?? '').isEmpty) {
      await onRequestAuth();
      if (!session.isAuthenticated || (session.token ?? '').isEmpty) {
        return;
      }
    }

    if (isDisposed()) return;
    _isSubmitting = true;
    _notify();

    try {
      await apiClient.postChapterComment(
        chapterId: nextChapterId,
        content: content,
      );
      textController.clear();
      onShowMessage('已发送评论');
      await load(page);
    } catch (error) {
      final String message = error is SiteApiException
          ? error.message
          : '评论发送失败，请稍后重试。';
      if (message.contains('登录已失效')) {
        await onLogoutForExpiredSession();
      }
      if (!isDisposed()) {
        onShowMessage(message);
      }
    } finally {
      _isSubmitting = false;
      _notify();
    }
  }

  void dispose() {
    textController.dispose();
    scrollController.dispose();
  }

  Future<(ChapterCommentFeed, int, int)> _loadInitialPage(
    String chapterId,
  ) async {
    final ChapterCommentFeed probe = await apiClient.loadChapterComments(
      chapterId: chapterId,
      limit: 1,
      offset: 0,
    );
    final int probeTotal = probe.total > 0
        ? probe.total
        : probe.comments.length;
    if (probeTotal <= 0) {
      return (probe, 0, 0);
    }

    final ReaderCommentPageWindow window = probeTotal <= 1
        ? const ReaderCommentPageWindow(offset: 0, limit: readerCommentPageSize)
        : initialCommentWindow(total: probeTotal);
    final ChapterCommentFeed rawFeed = await apiClient.loadChapterComments(
      chapterId: chapterId,
      limit: window.limit,
      offset: window.offset,
    );
    final int resolvedTotal = rawFeed.total > 0
        ? rawFeed.total
        : math.max(probeTotal, rawFeed.comments.length);
    return (
      ChapterCommentFeed(
        total: resolvedTotal,
        comments: normalizeCommentPage(rawFeed.comments),
      ),
      window.offset,
      resolvedTotal,
    );
  }

  Future<(ChapterCommentFeed, int, int)> _loadAscendingPage({
    required String chapterId,
    required ReaderCommentPageWindow window,
    required int fallbackTotal,
  }) async {
    final ChapterCommentFeed rawFeed = await apiClient.loadChapterComments(
      chapterId: chapterId,
      limit: window.limit,
      offset: window.offset,
    );
    final int resolvedTotal = rawFeed.total > 0 ? rawFeed.total : fallbackTotal;
    return (
      ChapterCommentFeed(
        total: resolvedTotal,
        comments: normalizeCommentPage(rawFeed.comments),
      ),
      window.offset,
      resolvedTotal,
    );
  }

  void _clearLoadingIfCurrent(String chapterId) {
    if (_chapterId != chapterId) {
      return;
    }
    _isLoading = false;
    _isLoadingMore = false;
    _notify();
  }

  void _notify() {
    if (!isDisposed()) {
      notify();
    }
  }
}
