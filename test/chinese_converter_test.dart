import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:reader/models/app_preferences.dart';
import 'package:reader/services/chinese_converter.dart';

class _FakeEngine implements ChineseConversionEngine {
  int convertCalls = 0;
  int disposeCalls = 0;

  @override
  String convert(String text) {
    convertCalls += 1;
    return '简:$text';
  }

  @override
  void dispose() {
    disposeCalls += 1;
  }
}

void main() {
  test('关闭模式不会创建引擎', () async {
    int factoryCalls = 0;
    final ChineseConverter converter = ChineseConverter(
      engineFactory: () {
        factoryCalls += 1;
        return _FakeEngine();
      },
    );
    addTearDown(converter.dispose);

    expect(await converter.setMode(ChineseConversionMode.disabled), isTrue);

    expect(factoryCalls, 0);
    expect(converter.isInitialized, isFalse);
    expect(converter.convert('繁體'), '繁體');
  });

  test('并发启用共享一次初始化且准备期间显示原文', () async {
    final Completer<ChineseConversionEngine> engineCompleter =
        Completer<ChineseConversionEngine>();
    final _FakeEngine engine = _FakeEngine();
    int factoryCalls = 0;
    final ChineseConverter converter = ChineseConverter(
      engineFactory: () {
        factoryCalls += 1;
        return engineCompleter.future;
      },
    );
    addTearDown(converter.dispose);

    final Future<bool> first = converter.setMode(ChineseConversionMode.t2s);
    final Future<bool> second = converter.setMode(ChineseConversionMode.t2s);

    expect(factoryCalls, 1);
    expect(converter.isInitializing, isTrue);
    expect(converter.convert('繁體'), '繁體');

    engineCompleter.complete(engine);

    expect(await first, isFalse);
    expect(await second, isTrue);
    expect(factoryCalls, 1);
    expect(converter.isInitialized, isTrue);
    expect(converter.currentMode, ChineseConversionMode.t2s);
    expect(converter.convert('繁體'), '简:繁體');
    expect(engine.convertCalls, 1);
  });

  test('初始化失败返回 false 并保持原文模式', () async {
    final ChineseConverter converter = ChineseConverter(
      engineFactory: () {
        throw StateError('engine unavailable');
      },
    );
    addTearDown(converter.dispose);

    expect(await converter.setMode(ChineseConversionMode.t2s), isFalse);

    expect(converter.currentMode, ChineseConversionMode.disabled);
    expect(converter.isInitialized, isFalse);
    expect(converter.lastInitializationError, isA<StateError>());
    expect(converter.convert('繁體'), '繁體');
  });

  test('初始化失败后再次启用会重新尝试', () async {
    final _FakeEngine engine = _FakeEngine();
    int factoryCalls = 0;
    final ChineseConverter converter = ChineseConverter(
      engineFactory: () {
        factoryCalls += 1;
        if (factoryCalls == 1) {
          throw StateError('first attempt failed');
        }
        return engine;
      },
    );
    addTearDown(converter.dispose);

    expect(await converter.setMode(ChineseConversionMode.t2s), isFalse);
    expect(await converter.setMode(ChineseConversionMode.t2s), isTrue);

    expect(factoryCalls, 2);
    expect(converter.lastInitializationError, isNull);
    expect(converter.convert('繁體'), '简:繁體');
  });

  test('快速关闭后迟到的启用结果不能覆盖最新模式', () async {
    final Completer<ChineseConversionEngine> engineCompleter =
        Completer<ChineseConversionEngine>();
    int factoryCalls = 0;
    final ChineseConverter converter = ChineseConverter(
      engineFactory: () {
        factoryCalls += 1;
        return engineCompleter.future;
      },
    );
    addTearDown(converter.dispose);

    final Future<bool> enable = converter.setMode(ChineseConversionMode.t2s);
    expect(await converter.setMode(ChineseConversionMode.disabled), isTrue);
    engineCompleter.complete(_FakeEngine());

    expect(await enable, isFalse);
    expect(factoryCalls, 1);
    expect(converter.currentMode, ChineseConversionMode.disabled);
    expect(converter.convert('繁體'), '繁體');
  });

  test('快速切换后的最后一次启用复用进行中的初始化', () async {
    final Completer<ChineseConversionEngine> engineCompleter =
        Completer<ChineseConversionEngine>();
    int factoryCalls = 0;
    final ChineseConverter converter = ChineseConverter(
      engineFactory: () {
        factoryCalls += 1;
        return engineCompleter.future;
      },
    );
    addTearDown(converter.dispose);

    final Future<bool> firstEnable = converter.setMode(
      ChineseConversionMode.t2s,
    );
    expect(await converter.setMode(ChineseConversionMode.disabled), isTrue);
    final Future<bool> lastEnable = converter.setMode(
      ChineseConversionMode.t2s,
    );
    engineCompleter.complete(_FakeEngine());

    expect(await firstEnable, isFalse);
    expect(await lastEnable, isTrue);
    expect(factoryCalls, 1);
    expect(converter.currentMode, ChineseConversionMode.t2s);
    expect(converter.convert('繁體'), '简:繁體');
  });

  test('模式就绪和关闭时通知独立显示层重建', () async {
    final Completer<ChineseConversionEngine> engineCompleter =
        Completer<ChineseConversionEngine>();
    final ChineseConverter converter = ChineseConverter(
      engineFactory: () => engineCompleter.future,
    );
    addTearDown(converter.dispose);
    int notifications = 0;
    converter.addListener(() {
      notifications += 1;
    });

    final Future<bool> enabling = converter.setMode(ChineseConversionMode.t2s);
    expect(notifications, 0);
    engineCompleter.complete(_FakeEngine());

    expect(await enabling, isTrue);
    expect(notifications, 1);
    expect(await converter.setMode(ChineseConversionMode.disabled), isTrue);
    expect(notifications, 2);
  });
}
