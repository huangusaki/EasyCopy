import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_opencc/flutter_opencc.dart';
import 'package:reader/models/app_preferences.dart';

typedef ChineseConversionDataLoader = Future<String> Function();
typedef ChineseConversionEngineFactory =
    FutureOr<ChineseConversionEngine> Function(String dataDir);

abstract interface class ChineseConversionEngine {
  String convert(String text);

  void dispose();
}

class _OpenCCChineseConversionEngine implements ChineseConversionEngine {
  _OpenCCChineseConversionEngine(String dataDir)
    : _converter = OpenCC(OpenCCConfig.t2s, dataDir: dataDir);

  final OpenCC _converter;

  @override
  String convert(String text) => _converter.convert(text);

  @override
  void dispose() => _converter.dispose();
}

/// 繁简转换服务
///
/// 封装 flutter_opencc，提供文本的繁简转换能力。
/// 使用单例模式，全局共享 Converter 实例以提高性能。
class ChineseConverter extends ChangeNotifier {
  ChineseConverter({
    ChineseConversionDataLoader? dataLoader,
    ChineseConversionEngineFactory? engineFactory,
  }) : _dataLoader = dataLoader ?? (() => OpenCCData.prepareData()),
       _engineFactory =
           engineFactory ??
           ((String dataDir) => _OpenCCChineseConversionEngine(dataDir));

  static final ChineseConverter instance = ChineseConverter();

  final ChineseConversionDataLoader _dataLoader;
  final ChineseConversionEngineFactory _engineFactory;

  ChineseConversionEngine? _t2sEngine;
  Future<ChineseConversionEngine?>? _initialization;
  int _modeRequestGeneration = 0;
  int _resourceGeneration = 0;
  Object? _lastInitializationError;

  /// 是否已初始化
  bool get isInitialized => _t2sEngine != null;

  /// 是否正在准备转换引擎
  bool get isInitializing => _initialization != null;

  /// 最近一次初始化错误
  Object? get lastInitializationError => _lastInitializationError;

  /// 获取当前转换模式
  ChineseConversionMode _currentMode = ChineseConversionMode.disabled;

  /// 当前转换模式
  ChineseConversionMode get currentMode => _currentMode;

  /// 设置转换模式
  ///
  /// 关闭模式不会加载 OpenCC。启用模式会异步准备唯一的转换引擎；准备期间
  /// [convert] 继续返回原文。返回 `false` 表示请求已过期或初始化失败。
  Future<bool> setMode(ChineseConversionMode mode) async {
    final int requestGeneration = ++_modeRequestGeneration;

    if (mode == ChineseConversionMode.disabled) {
      _updateCurrentMode(ChineseConversionMode.disabled);
      return true;
    }

    final ChineseConversionEngine? readyEngine = _t2sEngine;
    if (readyEngine != null) {
      _updateCurrentMode(ChineseConversionMode.t2s);
      return true;
    }

    _updateCurrentMode(ChineseConversionMode.disabled);
    final ChineseConversionEngine? engine = await _ensureEngine();
    if (requestGeneration != _modeRequestGeneration) {
      return false;
    }
    if (engine == null) {
      _updateCurrentMode(ChineseConversionMode.disabled);
      return false;
    }

    _updateCurrentMode(ChineseConversionMode.t2s);
    return true;
  }

  void _updateCurrentMode(ChineseConversionMode mode) {
    if (_currentMode == mode) {
      return;
    }
    _currentMode = mode;
    notifyListeners();
  }

  /// 转换单个文本
  ///
  /// 根据当前 [currentMode] 转换文本。
  /// 如果模式为 [ChineseConversionMode.disabled] 或文本为空，直接返回原文本。
  String convert(String text) {
    final ChineseConversionEngine? engine = _t2sEngine;
    if (_currentMode == ChineseConversionMode.disabled || engine == null) {
      return text;
    }
    if (text.isEmpty) return text;

    try {
      return engine.convert(text);
    } catch (_) {
      // 转换失败时返回原文
      return text;
    }
  }

  /// 批量转换文本列表
  List<String> convertAll(List<String> texts) {
    return texts.map(convert).toList(growable: false);
  }

  Future<ChineseConversionEngine?> _ensureEngine() {
    final ChineseConversionEngine? readyEngine = _t2sEngine;
    if (readyEngine != null) {
      return Future<ChineseConversionEngine?>.value(readyEngine);
    }

    final Future<ChineseConversionEngine?>? pending = _initialization;
    if (pending != null) {
      return pending;
    }

    final int resourceGeneration = _resourceGeneration;
    late final Future<ChineseConversionEngine?> initialization;
    initialization = _createEngine(resourceGeneration).whenComplete(() {
      if (identical(_initialization, initialization)) {
        _initialization = null;
      }
    });
    _initialization = initialization;
    return initialization;
  }

  Future<ChineseConversionEngine?> _createEngine(int resourceGeneration) async {
    try {
      _lastInitializationError = null;
      final String dataDir = await _dataLoader();
      if (resourceGeneration != _resourceGeneration) {
        return null;
      }

      final ChineseConversionEngine createdEngine =
          await Future<ChineseConversionEngine>.sync(
            () => _engineFactory(dataDir),
          );
      if (resourceGeneration != _resourceGeneration) {
        createdEngine.dispose();
        return null;
      }

      final ChineseConversionEngine? existingEngine = _t2sEngine;
      if (existingEngine != null) {
        createdEngine.dispose();
        return existingEngine;
      }
      _t2sEngine = createdEngine;
      return createdEngine;
    } catch (error) {
      if (resourceGeneration == _resourceGeneration) {
        _lastInitializationError = error;
      }
      return null;
    }
  }

  /// 清理资源
  @override
  void dispose() {
    _modeRequestGeneration += 1;
    _resourceGeneration += 1;
    _currentMode = ChineseConversionMode.disabled;
    _initialization = null;
    _lastInitializationError = null;
    _t2sEngine?.dispose();
    _t2sEngine = null;
    super.dispose();
  }
}
