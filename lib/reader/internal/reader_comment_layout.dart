class ReaderCommentBubbleMetrics {
  const ReaderCommentBubbleMetrics({required this.width, required this.height});

  final double width;
  final double height;
}

class ReaderCommentBubblePlacement {
  const ReaderCommentBubblePlacement({
    required this.index,
    required this.left,
    required this.top,
    required this.width,
  });

  final int index;
  final double left;
  final double top;
  final double width;
}

class ReaderCommentCloudLayout {
  const ReaderCommentCloudLayout({
    required this.height,
    required this.placements,
  });

  final double height;
  final List<ReaderCommentBubblePlacement> placements;
}
