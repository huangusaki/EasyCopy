import 'package:flutter/material.dart';
import 'package:reader/widgets/page_skeleton.dart';

/// 加载和入场动画只影响结果，不改变上方搜索框和筛选区。
class DiscoverResultsSliver extends StatefulWidget {
  const DiscoverResultsSliver({
    required this.resultKey,
    required this.isLoading,
    required this.onRetry,
    required this.sliver,
    this.errorMessage,
    super.key,
  });

  final String resultKey;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onRetry;
  final Widget sliver;

  @override
  State<DiscoverResultsSliver> createState() => _DiscoverResultsSliverState();
}

class _DiscoverResultsSliverState extends State<DiscoverResultsSliver>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  late final CurvedAnimation _opacity = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    if (!widget.isLoading && widget.errorMessage == null) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant DiscoverResultsSliver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isLoading &&
        widget.errorMessage == null &&
        (oldWidget.isLoading ||
            oldWidget.errorMessage != null ||
            oldWidget.resultKey != widget.resultKey)) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _opacity.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return const SliverToBoxAdapter(child: PageSkeleton.grid());
    }
    if (widget.errorMessage != null) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: <Widget>[
              const Text('加载失败'),
              const SizedBox(height: 8),
              TextButton(onPressed: widget.onRetry, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    return SliverFadeTransition(opacity: _opacity, sliver: widget.sliver);
  }
}
