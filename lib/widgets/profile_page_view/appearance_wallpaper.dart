part of '../profile_page_view.dart';

class _AppearanceSettingsCard extends StatelessWidget {
  const _AppearanceSettingsCard({
    required this.themePreference,
    this.onChanged,
    this.wallpaper = const WallpaperPreferences(),
    this.wallpaperActions,
  });

  final AppThemePreference themePreference;
  final ValueChanged<AppThemePreference>? onChanged;
  final WallpaperPreferences wallpaper;
  final WallpaperEditingActions? wallpaperActions;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return AppSurfaceCard(
      title: '外观',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '主题配色',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.72),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: AppThemePreference.values
                .map(
                  (AppThemePreference option) => _ThemeSwatch(
                    option: option,
                    selected: option == themePreference,
                    onTap: onChanged == null ? null : () => onChanged!(option),
                  ),
                )
                .toList(growable: false),
          ),
          if (wallpaperActions != null) ...<Widget>[
            const SizedBox(height: 20),
            Divider(
              height: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            _WallpaperSettingsSection(
              wallpaper: wallpaper,
              actions: wallpaperActions!,
            ),
          ],
        ],
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final AppThemePreference option;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color borderColor = selected
        ? colorScheme.primary
        : colorScheme.outlineVariant;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        width: 92,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: selected ? 2 : 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: double.infinity,
              height: 56,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  _buildPreview(option),
                  if (selected)
                    Center(
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colorScheme.primary,
                        ),
                        child: Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: colorScheme.onPrimary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              appThemePreferenceLabel(option),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildPreview(AppThemePreference option) {
    switch (option) {
      case AppThemePreference.system:
        return const Row(
          children: <Widget>[
            Expanded(child: ColoredBox(color: Color(0xFFFFFFFF))),
            Expanded(child: ColoredBox(color: Color(0xFF000000))),
          ],
        );
      case AppThemePreference.pureWhite:
        return const ColoredBox(color: Color(0xFFFFFFFF));
      case AppThemePreference.pureBlack:
        return const ColoredBox(color: Color(0xFF000000));
      case AppThemePreference.warmLight:
        return const ColoredBox(color: Color(0xFFFAF6EE));
      case AppThemePreference.warmDark:
        return const ColoredBox(color: Color(0xFF18130E));
      case AppThemePreference.lightOrange:
        return const ColoredBox(color: Color(0xFFFFF3E6));
      case AppThemePreference.softGreen:
        return const ColoredBox(color: Color(0xFFC7EDCC));
      case AppThemePreference.bluePink:
        return const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Color(0xFFC9D5FF),
                Color(0xFFEEDBF1),
                Color(0xFFFFCEDF),
              ],
            ),
          ),
        );
      case AppThemePreference.lightBlueGreen:
        return const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Color(0xFFC4E0FF),
                Color(0xFFD2E9DD),
                Color(0xFFC0E8CB),
              ],
            ),
          ),
        );
    }
  }
}

class _WallpaperSettingsSection extends StatefulWidget {
  const _WallpaperSettingsSection({
    required this.wallpaper,
    required this.actions,
  });

  final WallpaperPreferences wallpaper;
  final WallpaperEditingActions actions;

  @override
  State<_WallpaperSettingsSection> createState() =>
      _WallpaperSettingsSectionState();
}

class _WallpaperSettingsSectionState extends State<_WallpaperSettingsSection> {
  double? _draftBrightness;
  double? _draftBlur;
  bool _isPicking = false;

  @override
  Widget build(BuildContext context) {
    final WallpaperPreferences w = widget.wallpaper;
    final WallpaperEditingActions actions = widget.actions;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final double brightness = _draftBrightness ?? w.brightness;
    final double blur = _draftBlur ?? w.blurSigma;
    final bool hasImage = w.hasImage;
    final bool isEnabled = w.enabled;
    final bool controlsEnabled = hasImage && isEnabled && !_isPicking;
    final String statusLine = !hasImage
        ? '选择一张图片作为应用背景'
        : !isEnabled
        ? '已隐藏 · 打开开关即可启用'
        : '已启用 · 拖动滑块实时调节';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '自定义壁纸',
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.72),
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    statusLine,
                    style: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(
              value: isEnabled,
              onChanged: !hasImage || _isPicking
                  ? null
                  : (bool value) {
                      actions.commitPreferences(w.copyWith(enabled: value));
                    },
            ),
          ],
        ),
        const SizedBox(height: 12),
        _WallpaperPreviewTile(
          wallpaper: w,
          previewBrightness: brightness,
          previewBlur: blur,
          isLoading: _isPicking,
          onTap: _isPicking ? null : _handlePick,
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _isPicking ? null : _handlePick,
                icon: const Icon(Icons.image_outlined),
                label: Text(hasImage ? '更换图片' : '选择图片'),
              ),
            ),
            if (hasImage) ...<Widget>[
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _isPicking
                    ? null
                    : () {
                        actions.clearImage();
                      },
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('移除'),
              ),
            ],
          ],
        ),
        if (hasImage) ...<Widget>[
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isPicking ? null : _handleCrop,
              icon: const Icon(Icons.crop_rounded),
              label: const Text('裁剪选区'),
            ),
          ),
        ],
        if (hasImage) ...<Widget>[
          const SizedBox(height: 14),
          _WallpaperSliderRow(
            icon: Icons.brightness_6_outlined,
            label: '背景亮度',
            valueLabel: '${(brightness * 100).round()}%',
            value: brightness,
            min: 0.0,
            max: 1.0,
            divisions: 100,
            enabled: controlsEnabled,
            onChanged: (double value) {
              setState(() => _draftBrightness = value);
              actions.previewPreferences(w.copyWith(brightness: value));
            },
            onChangeEnd: (double value) {
              actions.commitPreferences(w.copyWith(brightness: value));
              setState(() => _draftBrightness = null);
            },
          ),
          const SizedBox(height: 4),
          _WallpaperSliderRow(
            icon: Icons.blur_on_outlined,
            label: '模糊度',
            valueLabel: blur < 0.5 ? '关闭' : '${blur.round()}',
            value: blur,
            min: 0.0,
            max: WallpaperPreferences.maxBlurSigma,
            divisions: WallpaperPreferences.maxBlurSigma.round(),
            enabled: controlsEnabled,
            onChanged: (double value) {
              setState(() => _draftBlur = value);
              actions.previewPreferences(w.copyWith(blurSigma: value));
            },
            onChangeEnd: (double value) {
              actions.commitPreferences(w.copyWith(blurSigma: value));
              setState(() => _draftBlur = null);
            },
          ),
        ],
      ],
    );
  }

  Future<void> _handlePick() async {
    if (_isPicking) {
      return;
    }
    setState(() => _isPicking = true);
    try {
      await widget.actions.pickImage();
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      } else {
        _isPicking = false;
      }
    }
  }

  Future<void> _handleCrop() async {
    final WallpaperPreferences w = widget.wallpaper;
    final String? path = WallpaperStorage.instance.resolvePathSync(
      w.imageFileName,
    );
    if (path == null) {
      return;
    }
    final Rect? result = await Navigator.of(context).push<Rect>(
      MaterialPageRoute<Rect>(
        fullscreenDialog: true,
        builder: (BuildContext context) => WallpaperCropEditorPage(
          imagePath: path,
          initialCrop: Rect.fromLTWH(
            w.cropLeft,
            w.cropTop,
            w.cropWidth,
            w.cropHeight,
          ),
        ),
      ),
    );
    if (result == null) {
      return;
    }
    widget.actions.commitPreferences(
      w.copyWith(
        cropLeft: result.left,
        cropTop: result.top,
        cropWidth: result.width,
        cropHeight: result.height,
      ),
    );
  }
}

class _WallpaperPreviewTile extends StatelessWidget {
  const _WallpaperPreviewTile({
    required this.wallpaper,
    required this.previewBrightness,
    required this.previewBlur,
    required this.isLoading,
    required this.onTap,
  });

  final WallpaperPreferences wallpaper;
  final double previewBrightness;
  final double previewBlur;
  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final String? path = WallpaperStorage.instance.resolvePathSync(
      wallpaper.imageFileName,
    );
    final double scrimAlpha = (1.0 - previewBrightness).clamp(0.0, 1.0);

    Widget content;
    if (path == null) {
      content = _buildPlaceholder(colorScheme);
    } else {
      content = Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Positioned.fill(
            child: CroppedWallpaperImage(
              path: path,
              cropLeft: wallpaper.cropLeft,
              cropTop: wallpaper.cropTop,
              cropWidth: wallpaper.cropWidth,
              cropHeight: wallpaper.cropHeight,
              blurSigma: previewBlur,
              fallback: _buildPlaceholder(colorScheme),
            ),
          ),
          if (scrimAlpha > 0.001)
            Positioned.fill(
              child: ColoredBox(
                color: colorScheme.surface.withValues(alpha: scrimAlpha),
              ),
            ),
          if (wallpaper.enabled)
            Positioned(
              right: 12,
              bottom: 12,
              child: _PreviewSampleCard(colorScheme: colorScheme),
            ),
          Positioned(
            left: 12,
            top: 12,
            child: _PreviewHintChip(
              colorScheme: colorScheme,
              label: wallpaper.enabled ? '当前壁纸' : '已隐藏',
            ),
          ),
        ],
      );
    }

    return Material(
      color: colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: AspectRatio(
          aspectRatio: 16 / 10,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              content,
              if (isLoading)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.3),
                    child: const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(ColorScheme colorScheme) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            colorScheme.primaryContainer.withValues(alpha: 0.6),
            colorScheme.secondaryContainer.withValues(alpha: 0.55),
            colorScheme.tertiaryContainer.withValues(alpha: 0.5),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.7),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.add_photo_alternate_outlined,
                color: colorScheme.primary,
                size: 28,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '点击选择壁纸图片',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.78),
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '支持 JPG / PNG / WEBP',
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.52),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewSampleCard extends StatelessWidget {
  const _PreviewSampleCard({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 60,
            height: 8,
            decoration: BoxDecoration(
              color: colorScheme.onSurface.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 90,
            height: 6,
            decoration: BoxDecoration(
              color: colorScheme.onSurface.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 72,
            height: 6,
            decoration: BoxDecoration(
              color: colorScheme.onSurface.withValues(alpha: 0.32),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewHintChip extends StatelessWidget {
  const _PreviewHintChip({required this.colorScheme, required this.label});

  final ColorScheme colorScheme;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 11,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _WallpaperSliderRow extends StatelessWidget {
  const _WallpaperSliderRow({
    required this.icon,
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final IconData icon;
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color disabledLabelColor = colorScheme.onSurface.withValues(
      alpha: 0.36,
    );
    final Color labelColor = enabled
        ? colorScheme.onSurface.withValues(alpha: 0.82)
        : disabledLabelColor;
    final Color iconColor = enabled ? colorScheme.primary : disabledLabelColor;
    final double clampedValue = value.clamp(min, max);
    return Row(
      children: <Widget>[
        Icon(icon, size: 18, color: iconColor),
        const SizedBox(width: 8),
        SizedBox(
          width: 64,
          child: Text(
            label,
            style: TextStyle(
              color: labelColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: clampedValue,
              min: min,
              max: max,
              divisions: divisions > 0 ? divisions : null,
              onChanged: enabled ? onChanged : null,
              onChangeEnd: enabled ? onChangeEnd : null,
            ),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 44,
          child: Text(
            valueLabel,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: labelColor,
              fontSize: 12,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}
