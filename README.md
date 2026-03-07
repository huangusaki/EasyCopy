# EasyCopy

![EasyCopy 新头像](assets/icons/app_icon_rounded_1024.png)

EasyCopy 是一个 Flutter 客户端，用来把 Copy 系漫画站的桌面网页重建成适合手机阅读的原生界面。

它不是简单地把网页塞进 WebView，而是把原站页面放到后台加载，提取结构化数据后再用 Flutter 渲染首页、发现、排行、详情、阅读和个人中心。这样既能沿用原站内容和账号体系，也能把移动端交互、缓存和阅读体验掌握在客户端里。

## 项目目标

- 隐藏桌面版网页壳，只保留站点内容和登录态
- 以原生方式重建移动端首页、发现、排行、详情和阅读体验
- 支持备用网址探测与自动切换，减少单一域名失效带来的影响
- 提供章节缓存、阅读进度恢复、页面缓存等移动端能力

## 已实现功能

### 1. 原生页面重建

- 首页：轮播、推荐区块、漫画卡片
- 发现页：筛选、分页、搜索结果、专题跳转
- 排行页：分类切换、时间维度切换、榜单卡片
- 详情页：封面、作者、标签、简介、章节列表、开始阅读
- 阅读页：图片流阅读、上一话 / 下一话、目录回跳
- 我的页面：用户信息、继续阅读、收藏、浏览历史

### 2. 登录与会话

- 支持直接调用站点登录接口进行原生登录
- 提供网页登录兜底，用于注册或处理特殊登录场景
- 统一保存 token 和 cookie，供 API 请求、WebView 和图片下载复用

### 3. 缓存与离线能力

- 页面缓存：按页面类型设置不同 TTL，并按登录作用域隔离
- 图片缓存：封面和阅读图片使用独立缓存策略
- 章节缓存：支持把整话图片保存到本地目录
- 后台队列：支持多章节排队、暂停、恢复、失败重试思路
- 已缓存漫画库：可浏览、继续打开、删除本地缓存

### 4. 可用节点切换

- 内置多个候选域名
- 启动时探测可用 host 并记录测速结果
- 主域异常时可以自动 failover 到其他可用节点
- 缓存页面中的站内链接会在恢复时重写到当前节点

### 5. 阅读体验

- 记录阅读进度并在回到章节时恢复位置
- 阅读页支持本地缓存章节与在线章节共存
- 详情页可识别已缓存章节并给出状态提示

## 真机截图

以下截图来自 Android 真机 fresh install 状态，不包含个人账号信息。

### 首页

![首页](docs/screenshots/home-fresh.png)

### 漫画详情

![漫画详情](docs/screenshots/detail-page.png)

### 阅读页

![阅读页](docs/screenshots/reader-page.png)

## 核心实现

### 页面获取链路

1. `WebView` 以桌面 UA 加载目标页面
2. 注入 `page_extractor_script.dart`，把 DOM 转成结构化 JSON
3. `EasyCopyScreen` 接收消息并恢复成 `EasyCopyPage`
4. Flutter 用原生组件重新渲染页面

### 关键模块

- `lib/easy_copy_screen.dart`
  - 主容器，负责导航、页面加载、阅读态和下载队列
- `lib/services/host_manager.dart`
  - 备用网址探测、选主和 failover
- `lib/services/page_repository.dart`
  - 页面缓存、内存缓存、重新验证
- `lib/services/site_api_client.dart`
  - 登录、个人中心接口、收藏与历史数据拉取
- `lib/services/site_session.dart`
  - token / cookie 持久化
- `lib/services/comic_download_service.dart`
  - 章节图片下载、本地 manifest、已缓存漫画库
- `lib/services/download_queue_store.dart`
  - 后台缓存队列持久化
- `lib/services/reader_progress_store.dart`
  - 阅读进度保存与恢复

### 页面模型

统一页面模型定义在 `lib/models/page_models.dart`，当前支持：

- `home`
- `discover`
- `rank`
- `detail`
- `reader`
- `profile`
- `unknown`

## 目录结构

```text
lib/
  config/      应用配置与导航定义
  models/      页面数据模型
  services/    Host、缓存、登录、下载等核心服务
  webview/     页面提取脚本
  widgets/     登录页、个人中心等独立组件
test/          单元测试、组件测试、HTML 夹具
docs/          README 使用的真机截图
android/       Android 工程
ios/           iOS 工程
macos/         macOS 工程
```

## 本地开发

当前仓库本地验证环境：

- Flutter 3.38.7
- Dart 3.10.7

### 安装依赖

```bash
flutter pub get
```

### 运行

```bash
flutter run
```

### Android 构建

```bash
flutter build apk --release --target-platform android-arm64
```

构建独立 `arm64-v8a` APK：

```bash
flutter build apk --release --target-platform=android-arm64 --split-per-abi
```

构建结果默认位于 `build/app/outputs/flutter-apk/`。

## 质量检查

```bash
flutter analyze
flutter test
```

## 测试覆盖重点

- Host 探测与切换
- 页面缓存读写与过期策略
- 下载队列持久化
- 章节缓存逻辑
- 个人中心数据解析
- 应用标题与基础组件行为

## 备注

- Android / iOS / macOS 原生工程标识已统一到 `com.huangusaki.easycopy`
- 项目强依赖目标站点的 DOM 结构和接口返回格式，不是通用爬虫框架
- `unknown` 页面类型表示该路由还没有完成原生重建
