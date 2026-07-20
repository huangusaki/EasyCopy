import 'package:flutter/material.dart';
import 'package:reader/widgets/responsive_layout.dart';

class PageSkeleton extends StatefulWidget {
  const PageSkeleton.grid({super.key}) : isDetail = false;

  const PageSkeleton.detail({super.key}) : isDetail = true;

  final bool isDetail;

  @override
  State<PageSkeleton> createState() => _PageSkeletonState();
}

class _PageSkeletonState extends State<PageSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);

  bool _configured = false;
  bool _useSweep = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_configured) {
      return;
    }
    _configured = true;
    _useSweep = usesWideLayout(context);
    if (_useSweep) {
      _controller.duration = const Duration(milliseconds: 1400);
      _controller.repeat();
    } else {
      _controller.duration = const Duration(milliseconds: 900);
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool isDark = colorScheme.brightness == Brightness.dark;
    final Color highlight = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.white.withValues(alpha: 0.45);

    final Widget bones = Padding(
      padding: standardContentPadding(context),
      // 视口裁剪，避免 RenderFlex overflow。
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: widget.isDetail
            ? const _DetailSkeleton()
            : const _GridSkeleton(),
      ),
    );

    final Widget animated = _useSweep
        ? AnimatedBuilder(
            animation: _controller,
            child: bones,
            builder: (BuildContext context, Widget? child) {
              return ShaderMask(
                blendMode: BlendMode.srcATop,
                shaderCallback: (Rect bounds) {
                  final double dx =
                      (_controller.value * 2 - 1) * bounds.width * 1.6;
                  return LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: <Color>[
                      Colors.transparent,
                      highlight,
                      Colors.transparent,
                    ],
                    stops: const <double>[0.32, 0.5, 0.68],
                  ).createShader(bounds.translate(dx, 0));
                },
                child: child,
              );
            },
          )
        : FadeTransition(
            opacity: Tween<double>(begin: 0.55, end: 1).animate(
              CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
            ),
            child: bones,
          );

    return ExcludeSemantics(child: RepaintBoundary(child: animated));
  }
}

class _Bone extends StatelessWidget {
  const _Bone({this.width, this.height = 14, this.radius = 8});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _GridSkeleton extends StatelessWidget {
  const _GridSkeleton();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        const double spacing = 12;
        final double maxWidth = constraints.maxWidth;
        final int crossAxisCount = responsiveComicCrossAxisCount(
          context,
          maxWidth,
          spacing: spacing,
        );
        final double itemWidth =
            (maxWidth - spacing * (crossAxisCount - 1)) / crossAxisCount;
        if (itemWidth <= 0) {
          return const SizedBox.shrink();
        }
        final double coverHeight = itemWidth / 0.72;

        Widget buildRow() {
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              children: <Widget>[
                for (
                  int column = 0;
                  column < crossAxisCount;
                  column += 1
                ) ...<Widget>[
                  if (column > 0) const SizedBox(width: spacing),
                  SizedBox(
                    width: itemWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _Bone(
                          width: itemWidth,
                          height: coverHeight,
                          radius: 16,
                        ),
                        const SizedBox(height: 8),
                        _Bone(width: itemWidth * 0.82, height: 12),
                        const SizedBox(height: 6),
                        _Bone(width: itemWidth * 0.55, height: 10),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: 4),
            const _Bone(width: 150, height: 18, radius: 6),
            const SizedBox(height: 16),
            buildRow(),
            buildRow(),
            const SizedBox(height: 10),
            const _Bone(width: 120, height: 18, radius: 6),
            const SizedBox(height: 16),
            buildRow(),
            buildRow(),
          ],
        );
      },
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) {
    final bool isWideLayout = usesWideLayout(context);
    final double coverWidth = isWideLayout ? 196 : 122;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _Bone(width: coverWidth, height: coverWidth / 0.72, radius: 20),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const _Bone(width: 240, height: 24, radius: 8),
                  const SizedBox(height: 14),
                  const Row(
                    children: <Widget>[
                      _Bone(width: 64, height: 26, radius: 999),
                      SizedBox(width: 8),
                      _Bone(width: 84, height: 26, radius: 999),
                      SizedBox(width: 8),
                      _Bone(width: 56, height: 26, radius: 999),
                    ],
                  ),
                  if (isWideLayout) ...<Widget>[
                    const SizedBox(height: 24),
                    const Row(
                      children: <Widget>[
                        _Bone(width: 138, height: 48, radius: 18),
                        SizedBox(width: 12),
                        _Bone(width: 126, height: 48, radius: 18),
                        SizedBox(width: 12),
                        _Bone(width: 126, height: 48, radius: 18),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (!isWideLayout) ...<Widget>[
          const SizedBox(height: 18),
          const Row(
            children: <Widget>[
              Expanded(child: _Bone(height: 44, radius: 18)),
              SizedBox(width: 12),
              Expanded(child: _Bone(height: 44, radius: 18)),
            ],
          ),
        ],
        const SizedBox(height: 22),
        const _Bone(width: 110, height: 16, radius: 6),
        const SizedBox(height: 12),
        const _Bone(height: 84, radius: 16),
        const SizedBox(height: 22),
        const _Bone(width: 110, height: 16, radius: 6),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            const double gap = 10;
            final int columns = isWideLayout ? 5 : 2;
            final double tileWidth =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: <Widget>[
                for (int index = 0; index < columns * 3; index += 1)
                  _Bone(width: tileWidth, height: 42, radius: 16),
              ],
            );
          },
        ),
      ],
    );
  }
}
