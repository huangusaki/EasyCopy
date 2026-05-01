import 'dart:math' as math;

import 'package:flutter/material.dart';

class ReaderProgressSeekBar extends StatefulWidget {
  const ReaderProgressSeekBar({
    required this.currentIndex,
    required this.totalCount,
    required this.onSeek,
    this.onInteraction,
    super.key,
  });

  final int currentIndex;
  final int totalCount;
  final VoidCallback? onInteraction;
  final ValueChanged<int> onSeek;

  @override
  State<ReaderProgressSeekBar> createState() => _ReaderProgressSeekBarState();
}

class _ReaderProgressSeekBarState extends State<ReaderProgressSeekBar> {
  late double _value;
  bool _scrubbing = false;

  int get _maxIndex => math.max(0, widget.totalCount - 1);

  @override
  void initState() {
    super.initState();
    _value = widget.currentIndex.clamp(0, _maxIndex).toDouble();
  }

  @override
  void didUpdateWidget(covariant ReaderProgressSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_scrubbing) {
      return;
    }
    final double nextValue = widget.currentIndex.clamp(0, _maxIndex).toDouble();
    if ((nextValue - _value).abs() < 0.5) {
      return;
    }
    _value = nextValue;
  }

  void _handleChangeStart(double _) {
    widget.onInteraction?.call();
    if (_scrubbing) {
      return;
    }
    setState(() {
      _scrubbing = true;
    });
  }

  void _handleChanged(double rawValue) {
    widget.onInteraction?.call();
    final int nextIndex = rawValue.round().clamp(0, _maxIndex);
    setState(() {
      _value = nextIndex.toDouble();
    });
  }

  void _handleChangeEnd(double rawValue) {
    final int nextIndex = rawValue.round().clamp(0, _maxIndex);
    setState(() {
      _scrubbing = false;
      _value = nextIndex.toDouble();
    });
    widget.onSeek(nextIndex);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.totalCount <= 0) {
      return const SizedBox.shrink();
    }
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final int current = _value.round().clamp(0, _maxIndex);
    final TextStyle numberStyle = TextStyle(
      color: colorScheme.onSurface.withValues(alpha: 0.76),
      fontSize: 12,
      fontWeight: FontWeight.w800,
    );
    return Row(
      children: <Widget>[
        SizedBox(
          width: 34,
          child: Text(
            '${current + 1}',
            textAlign: TextAlign.center,
            style: numberStyle,
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              inactiveTrackColor: colorScheme.outlineVariant.withValues(
                alpha: 0.65,
              ),
            ),
            child: Slider(
              value: _value.clamp(0, _maxIndex.toDouble()),
              min: 0,
              max: _maxIndex.toDouble(),
              onChangeStart: widget.totalCount > 1 ? _handleChangeStart : null,
              onChanged: widget.totalCount > 1 ? _handleChanged : null,
              onChangeEnd: widget.totalCount > 1 ? _handleChangeEnd : null,
            ),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            '${widget.totalCount}',
            textAlign: TextAlign.center,
            style: numberStyle,
          ),
        ),
      ],
    );
  }
}
