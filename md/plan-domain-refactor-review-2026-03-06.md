# 域名切换与项目重构计划（Plan v2）

## 用户原始需求
重构一下这个项目，现在网址改成：https://www.2026copy.com/了
另外修复一下你觉得不合理的地方，完全审查

## Plan 修订记录
- 已采纳：增加统一品牌命名，避免 `copy_fullter`、`Copy Fullter`、`2025Copy` 混用
- 已采纳：增加测试策略设计，避免 Widget Test 直接依赖真实 WebView 平台
- 已采纳：增加导航约束与错误恢复设计，补足加载失败和异常跳转处理
- 已采纳：明确根目录 HTML 文件仅做边界内修正，不做无意义结构重写
- 不采纳：本轮不做包名、applicationId、bundleId 级别重命名
- 不采纳原因：改动范围大、风险高、与“域名切换和结构重构”目标不成比例

## 技术方案设计（v2）

### 1. 总体架构思路
- 保持项目现有定位不变，继续作为 Flutter WebView 壳应用承载目标站点。
- 将当前集中在 `lib/web_view_screen.dart` 的域名、路由、注入脚本、页面状态控制进行拆分，降低单文件复杂度。
- 把“站点配置”“导航目标”“页面注入脚本”抽离为独立模块，避免再次出现整文件硬编码网址和超长字符串脚本。
- 同步清理 Flutter 模板残留，统一应用名称、文案、Web manifest 与平台展示信息，使项目从“默认模板”转为“可交付应用”状态。
- 本轮统一品牌名为 `2026Copy`，包名和应用 ID 保持不变，仅修正用户可见信息与代码结构。

### 2. 核心实现方式
- 新增统一站点配置层，集中管理基础域名 `https://www.2026copy.com/`、导航路径和应用名称。
- 对 WebView 页面进行重构：
  - 将控制器初始化逻辑与页面注入逻辑拆开。
  - 将注入脚本拆分为可组合的常量或构建函数，减少 `initState` 中的大段内联 JavaScript/CSS。
  - 规范加载态、错误态、返回逻辑与底部导航行为。
  - 增加导航约束，优先允许目标站点主机及站内相对路径，拦截明显异常 scheme。
  - 页面失败时提供可见错误态和重试入口，而不是只写日志。
- 将页面标题、Manifest、README、测试、平台显示名等统一替换为新的产品信息。
- 替换无效的默认计数器测试，改为符合当前项目实际的应用壳测试和纯 Dart 配置/路由测试。

### 3. 关键技术选型
- 继续使用现有 `webview_flutter`，不引入新的 WebView 技术栈。
- 使用 Dart 常量、简单的辅助类和文件拆分完成重构，避免过度设计。
- 保持现有 Material 3 应用壳，但补充更合理的主题名、标题和可维护性配置。

### 4. 测试策略设计
- 将域名、导航目标、路径拼接、页面标题等内容提炼为纯 Dart 可测试逻辑。
- Widget Test 避免直接依赖真实 `WebViewPlatform`，改测应用壳层级和可见 UI 结构。
- 真实页面加载与样式注入效果以手工验证为主，结合静态检查和测试通过作为交付基线。

## 影响范围分析

### 1. 涉及模块
- Flutter 应用入口
- WebView 容器页
- Web 平台配置
- Android/iOS/Desktop 平台展示信息
- 测试与项目说明文档

### 2. 涉及文件
- `lib/main.dart`
- `lib/web_view_screen.dart`
- 计划新增的 `lib/config/`、`lib/constants/` 或 `lib/webview/` 相关文件
- `test/widget_test.dart`
- `web/index.html`
- `web/manifest.json`
- `android/app/src/main/AndroidManifest.xml`
- `ios/Runner/Info.plist`
- `windows/runner/Runner.rc`
- `windows/CMakeLists.txt`
- `linux/CMakeLists.txt`
- `macos/Runner/Configs/AppInfo.xcconfig`
- `README.md`

### 3. 可能的风险点
- 目标站点 DOM 结构如果已有变化，当前选择器驱动的 CSS/JS 注入规则可能出现失效或副作用。
- `webview_flutter` 在 Widget Test 环境下不适合做真实页面加载测试，需要设计可执行的替代测试方式。
- 平台名称与二进制名调整若做得过深，可能带来包名、构建脚本或签名层面的额外改动；本次优先处理展示名和应用文案，不做高风险包名重命名。
- 根目录的 HTML 文件更像抓取快照或调试样本，若未纳入运行链路，不应在本轮随意重构其结构，但会按需修正其中明确的旧域名文本。
- 当前主要构建脚本指向 Android APK，因此 Android 作为主验证平台，其他平台只做低风险信息同步。

## 实施步骤概要（v2）
1. 方案确认阶段
   - 完成现状审查
   - 通过 Codex Review 校验方案完整性
2. 应用核心重构阶段
   - 提炼站点配置、品牌配置与导航目标
   - 拆分 WebView 初始化、脚本注入和页面策略逻辑
   - 修复返回逻辑、加载状态、错误态和导航约束
3. 工程治理阶段
   - 同步更新应用名称、Web 配置、平台展示名与 README
   - 清理模板残留、弃用 API 和明显不合理实现
4. 测试验证阶段
   - 重写无效默认测试并补充纯 Dart 测试
   - 执行 `flutter analyze` / `flutter test`
5. 收尾审查阶段
   - 编写实施文档
   - 进行实现结果复审并记录优化建议

## 实施 To-Do 列表
- [x] 新建站点与品牌配置文件，集中维护应用名称、基础域名、导航路径和允许主机
- [x] 新建 WebView 注入脚本模块，拆分页面通用脚本与样式脚本
- [x] 重构 `lib/web_view_screen.dart`，移除大段硬编码并补齐加载失败/重试/返回逻辑
- [x] 调整 `lib/main.dart`，接入统一品牌名称和更清晰的应用壳结构
- [x] 修正 `web/index.html` 与 `web/manifest.json` 的标题、描述和应用名称
- [x] 修正 Android、iOS、Windows、Linux、macOS 的用户可见应用名称
- [x] 更新根目录 HTML 样本中的明确旧域名文本
- [x] 重写 `test/widget_test.dart`，避免真实 WebView 平台依赖
- [x] 为纯 Dart 配置/导航逻辑补充测试
- [x] 更新 `README.md`
