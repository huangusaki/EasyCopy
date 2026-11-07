import 'package:flutter/foundation.dart';
import 'package:opencc_t2s/opencc_t2s.dart';
import 'package:reader/models/app_preferences.dart';

/// 全局共享繁简转换器及其文本缓存。
class ChineseConverter extends ChangeNotifier {
  static final ChineseConverter instance = ChineseConverter();

  final T2SConverter _converter = T2SConverter();
  ChineseConversionMode _currentMode = ChineseConversionMode.disabled;

  ChineseConversionMode get currentMode => _currentMode;

  void setMode(ChineseConversionMode mode) {
    if (_currentMode == mode) {
      return;
    }
    _currentMode = mode;
    notifyListeners();
  }

  String convert(String text) => _currentMode == ChineseConversionMode.disabled
      ? text
      : _converter.convert(text);

  @override
  void dispose() {
    _converter.clearCache();
    super.dispose();
  }
}
