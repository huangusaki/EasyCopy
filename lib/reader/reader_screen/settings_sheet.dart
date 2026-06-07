part of '../reader_screen.dart';

extension _ReaderSettingsSheet on ReaderScreenState {
  Widget _buildReaderSettingsSheet(BuildContext context) {
    final double maxHeight = MediaQuery.sizeOf(context).height * 0.78;
    final AppPreferencesController preferencesController =
        _controller.preferencesController;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: ColoredBox(
          color: colorScheme.surface.withValues(alpha: 0.78),
          child: AnimatedBuilder(
            animation: preferencesController,
            builder: (BuildContext context, Widget? _) {
              final ReaderPreferences preferences = _controller.preferences;
              return ReaderSheetSwipeDismissRegion(
                dismissDistance: _settingsDismissDistance,
                onDismiss: () => Navigator.of(context).maybePop(),
                child: SafeArea(
                  child: SizedBox(
                    key: const ValueKey<String>('reader-settings-sheet'),
                    height: maxHeight,
                    child: Column(
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.only(top: 10, bottom: 4),
                          child: Center(
                            child: Container(
                              width: 32,
                              height: 4,
                              decoration: BoxDecoration(
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.32,
                                ),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                            child: ListView(
                              children: <Widget>[
                                SettingsSection(
                                  children: <Widget>[
                                    SettingsSelectRow<ReaderScreenOrientation>(
                                      label: '屏幕方向',
                                      value: preferences.screenOrientation,
                                      items: ReaderScreenOrientation.values
                                          .map((ReaderScreenOrientation value) {
                                            return DropdownMenuItem<
                                              ReaderScreenOrientation
                                            >(
                                              value: value,
                                              child: Text(
                                                value ==
                                                        ReaderScreenOrientation
                                                            .portrait
                                                    ? '竖屏'
                                                    : '横屏',
                                              ),
                                            );
                                          })
                                          .toList(growable: false),
                                      onChanged:
                                          (ReaderScreenOrientation? value) {
                                            if (value == null) return;
                                            unawaited(
                                              preferencesController
                                                  .updateReaderPreferences(
                                                    (
                                                      ReaderPreferences current,
                                                    ) => current.copyWith(
                                                      screenOrientation: value,
                                                    ),
                                                  ),
                                            );
                                          },
                                    ),
                                    SettingsSelectRow<ReaderReadingDirection>(
                                      label: '阅读方向',
                                      value: preferences.readingDirection,
                                      items: ReaderReadingDirection.values
                                          .map((ReaderReadingDirection value) {
                                            return DropdownMenuItem<
                                              ReaderReadingDirection
                                            >(
                                              value: value,
                                              child: Text(switch (value) {
                                                ReaderReadingDirection
                                                    .topToBottom =>
                                                  '从上到下',
                                                ReaderReadingDirection
                                                    .leftToRight =>
                                                  '从左到右',
                                                ReaderReadingDirection
                                                    .rightToLeft =>
                                                  '从右到左',
                                              }),
                                            );
                                          })
                                          .toList(growable: false),
                                      onChanged:
                                          (ReaderReadingDirection? value) {
                                            if (value == null) return;
                                            unawaited(
                                              preferencesController
                                                  .updateReaderPreferences(
                                                    (
                                                      ReaderPreferences current,
                                                    ) => current.copyWith(
                                                      readingDirection: value,
                                                    ),
                                                  ),
                                            );
                                          },
                                    ),
                                    SettingsSelectRow<ReaderPageFit>(
                                      label: '页面缩放',
                                      value: preferences.pageFit,
                                      items: ReaderPageFit.values
                                          .map((ReaderPageFit value) {
                                            return DropdownMenuItem<
                                              ReaderPageFit
                                            >(
                                              value: value,
                                              child: Text(
                                                value == ReaderPageFit.fitWidth
                                                    ? '匹配宽度'
                                                    : '适应屏幕',
                                              ),
                                            );
                                          })
                                          .toList(growable: false),
                                      onChanged: (ReaderPageFit? value) {
                                        if (value == null) return;
                                        unawaited(
                                          preferencesController
                                              .updateReaderPreferences(
                                                (ReaderPreferences current) =>
                                                    current.copyWith(
                                                      pageFit: value,
                                                    ),
                                              ),
                                        );
                                      },
                                    ),
                                    SettingsSelectRow<ReaderOpeningPosition>(
                                      label: '开页位置',
                                      value: preferences.openingPosition,
                                      items: ReaderOpeningPosition.values
                                          .map((ReaderOpeningPosition value) {
                                            return DropdownMenuItem<
                                              ReaderOpeningPosition
                                            >(
                                              value: value,
                                              child: Text(
                                                value ==
                                                        ReaderOpeningPosition
                                                            .top
                                                    ? '顶部'
                                                    : '中心',
                                              ),
                                            );
                                          })
                                          .toList(growable: false),
                                      onChanged:
                                          (ReaderOpeningPosition? value) {
                                            if (value == null) return;
                                            unawaited(
                                              preferencesController
                                                  .updateReaderPreferences(
                                                    (
                                                      ReaderPreferences current,
                                                    ) => current.copyWith(
                                                      openingPosition: value,
                                                    ),
                                                  ),
                                            );
                                          },
                                    ),
                                    SettingsSliderRow(
                                      label:
                                          '自动翻页(${preferences.autoPageTurnSeconds}秒)',
                                      value: preferences.autoPageTurnSeconds
                                          .toDouble(),
                                      max: 10,
                                      divisions: 10,
                                      onChanged: (double value) {
                                        unawaited(
                                          preferencesController
                                              .updateReaderPreferences(
                                                (ReaderPreferences current) =>
                                                    current.copyWith(
                                                      autoPageTurnSeconds: value
                                                          .round(),
                                                    ),
                                              ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                SettingsSection(
                                  children: <Widget>[
                                    SettingsSwitchRow(
                                      label: '显示评论页',
                                      value: preferences.showChapterComments,
                                      onChanged: (bool value) {
                                        unawaited(
                                          preferencesController
                                              .updateReaderPreferences(
                                                (ReaderPreferences current) =>
                                                    current.copyWith(
                                                      showChapterComments:
                                                          value,
                                                    ),
                                              ),
                                        );
                                      },
                                    ),
                                    SettingsSwitchRow(
                                      label: '屏幕常亮',
                                      value: preferences.keepScreenOn,
                                      onChanged: (bool value) {
                                        unawaited(
                                          preferencesController
                                              .updateReaderPreferences(
                                                (ReaderPreferences current) =>
                                                    current.copyWith(
                                                      keepScreenOn: value,
                                                    ),
                                              ),
                                        );
                                      },
                                    ),
                                    SettingsSwitchRow(
                                      label: '显示时钟',
                                      value: preferences.showClock,
                                      onChanged: (bool value) {
                                        unawaited(
                                          preferencesController
                                              .updateReaderPreferences(
                                                (ReaderPreferences current) =>
                                                    current.copyWith(
                                                      showClock: value,
                                                    ),
                                              ),
                                        );
                                      },
                                    ),
                                    SettingsSwitchRow(
                                      label: '显示进度',
                                      value: preferences.showProgress,
                                      onChanged: (bool value) {
                                        unawaited(
                                          preferencesController
                                              .updateReaderPreferences(
                                                (ReaderPreferences current) =>
                                                    current.copyWith(
                                                      showProgress: value,
                                                    ),
                                              ),
                                        );
                                      },
                                    ),
                                    if (_controller
                                        .platformBridge
                                        .isAndroidSupported)
                                      SettingsSwitchRow(
                                        label: '显示电量',
                                        value: preferences.showBattery,
                                        onChanged: (bool value) {
                                          unawaited(
                                            preferencesController
                                                .updateReaderPreferences(
                                                  (ReaderPreferences current) =>
                                                      current.copyWith(
                                                        showBattery: value,
                                                      ),
                                                ),
                                          );
                                        },
                                      ),
                                    SettingsSwitchRow(
                                      label: '显示页面间隔',
                                      value: preferences.showPageGap,
                                      onChanged: (bool value) {
                                        unawaited(
                                          preferencesController
                                              .updateReaderPreferences(
                                                (ReaderPreferences current) =>
                                                    current.copyWith(
                                                      showPageGap: value,
                                                    ),
                                              ),
                                        );
                                      },
                                    ),
                                    if (_controller
                                        .platformBridge
                                        .isAndroidSupported)
                                      SettingsSwitchRow(
                                        label: '使用音量键翻页',
                                        value:
                                            preferences.useVolumeKeysForPaging,
                                        onChanged: (bool value) {
                                          unawaited(
                                            preferencesController
                                                .updateReaderPreferences(
                                                  (ReaderPreferences current) =>
                                                      current.copyWith(
                                                        useVolumeKeysForPaging:
                                                            value,
                                                      ),
                                                ),
                                          );
                                        },
                                      ),
                                    SettingsSwitchRow(
                                      label: '全屏',
                                      value: preferences.fullscreen,
                                      onChanged: (bool value) {
                                        unawaited(
                                          preferencesController
                                              .updateReaderPreferences(
                                                (ReaderPreferences current) =>
                                                    current.copyWith(
                                                      fullscreen: value,
                                                    ),
                                              ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
