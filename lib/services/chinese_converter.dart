import 'package:flutter_opencc/flutter_opencc.dart';
import 'package:reader/models/app_preferences.dart';

/// 繁简转换服务
///
/// 封装 flutter_opencc，提供文本的繁简转换能力。
/// 使用单例模式，全局共享 Converter 实例以提高性能。
class ChineseConverter {
  ChineseConverter._();

  static final ChineseConverter instance = ChineseConverter._();

  String? _dataDir;
  OpenCC? _t2sConverter;
  bool _initialized = false;

  /// 是否已初始化
  bool get isInitialized => _initialized;

  /// 获取当前转换模式
  ChineseConversionMode _currentMode = ChineseConversionMode.disabled;

  /// 当前转换模式
  ChineseConversionMode get currentMode => _currentMode;

  /// 初始化 OpenCC 数据目录
  ///
  /// 从 Flutter Asset Bundle 提取内建字典到本地文件系统。
  /// 多次调用安全，已初始化后会跳过。
  Future<void> initialize() async {
    if (_initialized) return;
    _dataDir = await OpenCCData.prepareData();
    _initialized = true;
  }

  /// 初始化并设置转换模式
  Future<void> initializeWithMode(ChineseConversionMode mode) async {
    await initialize();
    _currentMode = mode;
  }

  /// 设置转换模式
  void setMode(ChineseConversionMode mode) {
    _currentMode = mode;
  }

  /// 转换单个文本
  ///
  /// 根据当前 [currentMode] 转换文本。
  /// 如果模式为 [ChineseConversionMode.disabled] 或文本为空，直接返回原文本。
  String convert(String text) {
    if (!_initialized || _currentMode == ChineseConversionMode.disabled) {
      return text;
    }
    if (text.isEmpty) return text;

    try {
      switch (_currentMode) {
        case ChineseConversionMode.disabled:
          return text;
        case ChineseConversionMode.t2s:
          _t2sConverter ??= OpenCC(OpenCCConfig.t2s, dataDir: _dataDir!);
          return _t2sConverter!.convert(text);
      }
    } catch (e) {
      // 转换失败时返回原文
      return text;
    }
  }

  /// 批量转换文本列表
  List<String> convertAll(List<String> texts) {
    return texts.map(convert).toList(growable: false);
  }

  /// 清理资源
  void dispose() {
    _t2sConverter?.dispose();
    _t2sConverter = null;
    _initialized = false;
  }
}
