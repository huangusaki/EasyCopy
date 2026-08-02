# opencc_t2s

纯 Dart 实现的繁体中文转简体中文工具。

## 缘由

本应用仅需要 OpenCC 的 `t2s`（繁转简）方向，且 `t2s.json` 中并未声明 `segmentation`（分词）。这使得整个转换过程只需进行两次字典匹配——完全不需要调用 OpenCC 的 mmseg、marisa 或 darts 等算法引擎。如果引入原生库，每个 ABI 将增加约 1.7 MB 的体积，此外还需要打包 1.19 MB 的 `.ocd2` 资源文件，而其中 `t2s` 实际仅用到了大约 92 KB。

## 使用方法

```dart
import 'package:opencc_t2s/opencc_t2s.dart';

final T2SConverter converter = T2SConverter();
converter.convert('進擊的巨人'); // 进击的巨人
```

`T2SConverter` 会对最近的 4096 次转换进行记忆化缓存，因为调用方通常会在每次重新构建（rebuild）时重复转换相同的标题。传入 `cacheSize: 0` 可以禁用该缓存，或者调用 `clearCache()` 来清空缓存。

字典表为 `static final`，因此它们仅在首次转换时构建一次（耗时约 2 毫秒），并由所有实例共享。

## 算法

忠实于 `t2s.json` 的实现：

1. **归一化** —— 对“中日韩兼容汉字”（`CJK_Compatibility_Ideographs`）进行一次贪婪匹配。
2. **转换** —— 对短路组（`short_circuit`）`[TSPhrases, TSCharactersExt, TSCharacters]` 进行自左向右的最长前缀贪婪匹配。在某个位置首个匹配成功的字典将生效，并采用该字典中最长的键；未匹配的码点将原样复制。

引入 `TSCharactersExt` 是因为 OpenCC 的 `includeTofuRiskDictionaries`（包含无法显示字符风险的字典）默认值为 `true`，这也是原生绑定所采用的配置。

### 与 OpenCC 的已知差异

表意文字描述字符序列（IDS，U+2FF0–U+2FFF）未被视为原子（整体）进行处理：OpenCC 会整体跳过未匹配 of IDS 序列，而本库会像处理其他文本一样，转换该序列内部的字符。

## 重新生成字典

`lib/src/dictionary_data.dart` 是自动生成的。它需要本地有一份 OpenCC 源码——本 package 自身并未内置：

```sh
git clone https://github.com/BYVoid/OpenCC /tmp/OpenCC
dart run tool/generate_dictionary.dart --opencc /tmp/OpenCC
```

`TSCharacters` 中将键映射为自身的条目会被丢弃：因为它是该组中的最后一个字典，且其所有键均为单个码点，所以保留此类条目与完全不包含该条目所产生的输出是相同的。生成器会断言这一不变性约束，如果上游打破了这一规律，生成则会失败。

转换的准确性由父项目中的 `test/opencc_t2s_test.dart` 进行保障，该测试会运行 OpenCC 官方的 `t2s` 测试用例。

## 开源协议

代码：采用与父项目相同的开源协议。`lib/src/dictionary_data.dart` 中的字典数据源自 [OpenCC](https://github.com/BYVoid/OpenCC)，采用 Apache-2.0 协议；详情请参阅根目录下的 `NOTICE` 文件。