import 'package:flutter/widgets.dart';

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

class ReaderCommentEmptyStateLayout extends StatelessWidget {
  const ReaderCommentEmptyStateLayout({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.center,
      heightFactor: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: child,
      ),
    );
  }
}
