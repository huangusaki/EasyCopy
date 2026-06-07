// ignore_for_file: use_key_in_widget_constructors

part of '../widgets.dart';

class PagerCard extends StatelessWidget {
  const PagerCard({
    required this.pager,
    required this.onPrev,
    required this.onNext,
    this.onJumpToPage,
  });

  final PagerData pager;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final ValueChanged<int>? onJumpToPage;

  void _runAction(BuildContext context, VoidCallback? action) {
    FocusScope.of(context).unfocus();
    action?.call();
  }

  Future<void> _openJumpSheet(BuildContext context) async {
    final int? totalPageCount = pager.totalPageCount;
    final int currentPage =
        pager.currentPageNumber ?? int.tryParse(pager.currentLabel) ?? 1;
    final int? target = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (BuildContext sheetContext) {
        return _PagerJumpSheet(
          totalPageCount: totalPageCount,
          currentPage: currentPage,
        );
      },
    );
    if (target != null && context.mounted) {
      onJumpToPage?.call(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final int? totalPageCount = pager.totalPageCount;
    final String currentDisplay =
        pager.currentPageNumber?.toString() ??
        (pager.currentLabel.isEmpty ? '--' : pager.currentLabel);
    final String totalDisplay = totalPageCount?.toString() ?? '';
    final bool jumpable = onJumpToPage != null;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        _PagerSideButton(
          icon: Icons.arrow_back_rounded,
          onPressed: onPrev == null ? null : () => _runAction(context, onPrev),
        ),
        const SizedBox(width: 10),
        _PagerIndicatorChip(
          current: currentDisplay,
          total: totalDisplay,
          enabled: jumpable,
          onTap: jumpable ? () => _openJumpSheet(context) : null,
        ),
        const SizedBox(width: 10),
        _PagerSideButton(
          icon: Icons.arrow_forward_rounded,
          onPressed: onNext == null ? null : () => _runAction(context, onNext),
        ),
      ],
    );
  }
}

class _PagerSideButton extends StatelessWidget {
  const _PagerSideButton({required this.icon, this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool enabled = onPressed != null;
    final Color background = enabled
        ? colorScheme.surfaceContainerHigh
        : colorScheme.surfaceContainerLow.withValues(alpha: 0.6);
    final Color foreground = enabled
        ? colorScheme.onSurface
        : colorScheme.onSurface.withValues(alpha: 0.32);
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 48,
          height: 44,
          child: Icon(icon, size: 22, color: foreground),
        ),
      ),
    );
  }
}

class _PagerIndicatorChip extends StatelessWidget {
  const _PagerIndicatorChip({
    required this.current,
    required this.total,
    required this.enabled,
    this.onTap,
  });

  final String current;
  final String total;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool hasTotal = total.isNotEmpty;
    return Material(
      color: colorScheme.secondaryContainer.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                current,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: colorScheme.onSecondaryContainer,
                  height: 1,
                ),
              ),
              if (hasTotal) ...<Widget>[
                Text(
                  ' / ',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSecondaryContainer.withValues(
                      alpha: 0.55,
                    ),
                    height: 1,
                  ),
                ),
                Text(
                  total,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSecondaryContainer.withValues(
                      alpha: 0.7,
                    ),
                    height: 1,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PagerJumpSheet extends StatefulWidget {
  const _PagerJumpSheet({
    required this.totalPageCount,
    required this.currentPage,
  });

  final int? totalPageCount;
  final int currentPage;

  @override
  State<_PagerJumpSheet> createState() => _PagerJumpSheetState();
}

class _PagerJumpSheetState extends State<_PagerJumpSheet> {
  late int _selectedPage;
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _selectedPage = _clampToRange(widget.currentPage);
    _textController = TextEditingController(text: _selectedPage.toString());
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  int _clampToRange(int value) {
    final int? total = widget.totalPageCount;
    if (total == null || total <= 0) {
      return value < 1 ? 1 : value;
    }
    if (value < 1) return 1;
    if (value > total) return total;
    return value;
  }

  void _setPage(int value, {bool syncText = true}) {
    final int next = _clampToRange(value);
    setState(() {
      _selectedPage = next;
      if (syncText) {
        _textController.value = TextEditingValue(
          text: next.toString(),
          selection: TextSelection.collapsed(offset: next.toString().length),
        );
      }
    });
  }

  void _confirm() {
    Navigator.of(context).pop(_selectedPage);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final int? total = widget.totalPageCount;
    final bool sliderEnabled = total != null && total > 1;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        4,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: Text(
                  '跳转到指定页',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              if (total != null)
                Text(
                  '共 $total 页',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              _PagerStepButton(
                icon: Icons.first_page_rounded,
                label: '首页',
                onPressed: sliderEnabled ? () => _setPage(1) : null,
              ),
              const SizedBox(width: 8),
              _PagerStepButton(
                icon: Icons.fast_rewind_rounded,
                label: '-10',
                onPressed: sliderEnabled
                    ? () => _setPage(_selectedPage - 10)
                    : null,
              ),
              const Spacer(),
              _PagerStepButton(
                icon: Icons.fast_forward_rounded,
                label: '+10',
                onPressed: sliderEnabled
                    ? () => _setPage(_selectedPage + 10)
                    : null,
              ),
              const SizedBox(width: 8),
              _PagerStepButton(
                icon: Icons.last_page_rounded,
                label: '尾页',
                onPressed: sliderEnabled ? () => _setPage(total) : null,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (sliderEnabled)
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: colorScheme.primary,
                inactiveTrackColor: colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.6),
                thumbColor: colorScheme.primary,
                overlayColor: colorScheme.primary.withValues(alpha: 0.18),
                trackHeight: 4,
              ),
              child: Slider(
                value: _selectedPage.toDouble().clamp(1, total.toDouble()),
                min: 1,
                max: total.toDouble(),
                divisions: total - 1,
                label: _selectedPage.toString(),
                onChanged: (double value) => _setPage(value.round()),
              ),
            )
          else
            const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _textController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.go,
                  textAlign: TextAlign.center,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: total == null ? '页码' : '1 - $total',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                  ),
                  onChanged: (String value) {
                    final int? parsed = int.tryParse(value.trim());
                    if (parsed != null) {
                      _setPage(parsed, syncText: false);
                    }
                  },
                  onSubmitted: (_) => _confirm(),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  onPressed: _confirm,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  label: const Text(
                    '前往',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PagerStepButton extends StatelessWidget {
  const _PagerStepButton({
    required this.icon,
    required this.label,
    this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool enabled = onPressed != null;
    final Color background = enabled
        ? colorScheme.surfaceContainerHigh
        : colorScheme.surfaceContainerLow.withValues(alpha: 0.6);
    final Color foreground = enabled
        ? colorScheme.onSurface
        : colorScheme.onSurface.withValues(alpha: 0.32);
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 16, color: foreground),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: foreground,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
