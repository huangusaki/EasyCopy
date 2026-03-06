# 域名切换与项目重构实施记录

## 任务概述
- 将应用内站点地址从 `https://www.2025copy.com/` 切换为 `https://www.2026copy.com/`
- 重构 WebView 壳层代码，拆分配置、导航与页面注入逻辑
- 清理模板残留，补齐测试、平台名称和基础文档

## 文件变更清单

### 新建文件
- `lib/copy_app.dart`
- `lib/config/app_config.dart`
- `lib/webview/webview_scripts.dart`
- `test/app_config_test.dart`

### 修改文件
- `lib/main.dart`
- `lib/web_view_screen.dart`
- `test/widget_test.dart`
- `web/index.html`
- `web/manifest.json`
- `android/app/src/main/AndroidManifest.xml`
- `ios/Runner/Info.plist`
- `windows/runner/main.cpp`
- `windows/runner/Runner.rc`
- `linux/runner/my_application.cc`
- `macos/Runner/Configs/AppInfo.xcconfig`
- `pubspec.yaml`
- `README.md`
- `homepage.html`
- `comics.html`
- `rank.html`
- `series.html`

## 核心代码说明

### 1. 统一站点配置
- 在 `lib/config/app_config.dart` 中集中管理应用名称、基础域名、允许主机和底部导航目标
- 增加 `resolvePath` 与 `tabIndexForUri`，把原来的硬编码 URL 切换为可复用配置逻辑

### 2. WebView 页面重构
- 在 `lib/web_view_screen.dart` 中重写页面状态管理
- 增加：
  - 加载态
  - 主帧错误态
  - 手动重试入口
  - 返回键回退 WebView 历史，否则退出应用
  - 导航主机约束，阻断明显异常外链 scheme

### 3. 注入脚本拆分
- 在 `lib/webview/webview_scripts.dart` 中将原本内联在页面里的脚本拆为：
  - viewport 处理脚本
  - 漫画阅读懒加载触发脚本
  - 移动端样式注入脚本
- 页面完成加载后按顺序注入，避免 `web_view_screen.dart` 继续膨胀

### 4. 测试策略修复
- 删除无效默认计数器测试
- 使用 `CopyApp(home: ...)` 作为可测试入口，避免 Widget Test 直接构建真实 WebView
- 为域名、导航映射和允许主机逻辑补充纯 Dart 测试

## 接口文档
- 本次未新增后端 API 或对外接口
- 应用内底部导航目标更新为：
  - `/`
  - `/comics`
  - `/rank`
  - `/web/login?url=person/home`

## 测试验证
- `flutter analyze`
  - 通过
- `flutter test`
  - 通过，4 个测试全部成功
- `.\build_arm64.ps1`
  - 成功产出 `build\app\outputs\flutter-apk\app-release.apk`

## 待优化项
- 页面 CSS/JS 注入仍依赖目标站点现有 DOM 结构，站点改版后需要重新校准选择器
- Android Release 构建完成后，Kotlin daemon 仍打印一段增量缓存关闭异常日志，当前不影响 APK 产物生成，但建议后续排查构建环境与缓存根路径差异
- 包名、applicationId、bundleId 仍保留模板值，出于风险控制本轮未做高影响重命名
