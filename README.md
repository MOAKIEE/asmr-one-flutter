# ASMR One · Flutter 客户端

基于 [asmr.one](https://asmr.one) 公开接口实现的第三方 Android 客户端，使用 Flutter 编写。

![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter&logoColor=white)
![Platform](https://img.shields.io/badge/platform-Android-3DDC84?logo=android&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.13-0175C2?logo=dart&logoColor=white)

> [!IMPORTANT]
> **免责声明**：本项目是**非官方**的第三方客户端，与 asmr.one 及 DLsite 无任何隶属或合作关系。
> 所有作品数据、封面与音频均通过 asmr.one 的公开接口获取，本项目不存储、不分发任何受版权保护的内容。
> 项目仅用于 Flutter 客户端开发的学习与技术交流，请勿用于商业用途。
>
> **内容提示**：目标站点包含成人向内容。应用内置了内容分级筛选与封面打码开关，
> 未满 18 岁请勿使用；请遵守你所在地区关于此类内容的法律法规。

---

## 一、接口调研结论

站点前端是 Nuxt/Vue 单页应用，接口统一挂在 `https://api.asmr.one/api` 下，
并在多个镜像线路之间切换。App 复刻了这套线路机制。

### 线路

```
https://api.asmr.one
https://api.asmr-100.com
https://api.asmr-200.com
https://api.asmr-300.com
```

`ApiClient` 在某条线路发生连接错误 / 超时 / 5xx 时会自动改用下一条并重试。

### 鉴权

* 请求头：`Authorization: Bearer <jwt>`，token 由 `POST /api/login` 返回。
* 未登录状态下，作品列表、详情、曲目、搜索、封面均可直接访问。
* 登录后额外解锁：完整标签库、评论、播放列表、推荐接口，以及**付费作品**的音频流。

### 已接入的端点

| 用途 | 方法与路径 | 是否需要登录 |
| --- | --- | --- |
| 作品列表 / 筛选 | `GET /api/works` | 否 |
| 作品详情 | `GET /api/work/{id}` | 否 |
| 曲目树 | `GET /api/tracks/{id}` | 否 |
| 关键词搜索 | `GET /api/search/{keyword}` | 否 |
| 封面图 | `GET /api/cover/{id}.jpg?type=main\|sam\|240x240` | 否 |
| 会话/能力开关 | `GET /api/auth/me` | 否（带 token 时返回用户） |
| 登录 | `POST /api/login` | 否 |
| 注册 | `POST /api/auth/reg` | 否 |
| 标签目录 | `GET /api/tags` | 是 |
| 评论列表 | `GET /api/review?workId=&page=&pageSize=` | 是 |
| 提交评分/评论 | `POST /api/review` | 是 |
| 标签投票 | `POST /api/vote/vote-work-tag` | 是 |
| 我的播放列表 | `GET /api/playlist/my-playlists` | 是 |
| 播放列表详情 | `GET /api/playlist/get-playlist-metadata?id=` | 是 |
| 新建播放列表 | `POST /api/playlist/create-playlist` | 是 |
| 加入 / 移出作品 | `POST /api/playlist/add-works-to-playlist` · `remove-works-from-playlist` | 是 |
| 默认收藏夹 | `GET /api/playlist/get-default-mark-target-playlist` | 是 |
| 收藏状态查询 | `GET /api/playlist/get-work-exist-status-in-my-playlists` | 是 |
| 音频流 | `GET /api/media/stream/{hash}?token=` | 付费内容需要 |
| 音频下载 | `GET /api/media/download/{hash}?token=` | 付费内容需要 |

`GET /api/works` 支持的查询参数：

```
page, pageSize
order  = create_date | release | dl_count | rate_average_2dp | review_count | price | id | random | betterRandom
sort   = desc | asc
keyword, tags(逗号分隔 id), circle(逗号分隔 id), vas(逗号分隔 id)
rate(最低评分 0~5), duration(最短时长/秒)
subtitle=1, includeTranslationWorks=1, nsfw=true|false
```

### 音频地址解析策略

1. 免费作品：曲目节点自带 CDN 直链（`mediaStreamUrl`），直接播放。
2. 付费作品：`mediaStreamUrl` 为空，登录后用 `hash` 拼接
   `/api/media/stream/{hash}?token=<jwt>`。
3. 已下载到本地的曲目优先读取本地文件。

### 内置标签目录

未登录时 `/api/tags` 不可用，因此 `lib/core/data/tag_catalog.dart` 内置了
260 条热门标签（含中/日/英三语名）。该文件由 `tool/gen_tag_catalog.py`
扫描作品列表聚合生成；登录后会改用服务端返回的完整目录。

---

## 二、功能一览

**浏览与发现**
- 首页五个榜单横滑区（热门下载 / 最新上架 / 高分好评 / 评论最多 / 免费高分）
- 「随便听听」随机跳转一部作品
- 网格与列表两种布局，网格列数 1~4 可调
- 排序：上架时间 / 发售日 / 下载量 / 评分 / 评论数 / 价格，升降序切换
- 筛选：标签多选、最低评分、最短时长、仅带字幕、包含翻译版、内容分级
- 标签浏览页与标签选择器（搜索、多选、已选计数）

**作品详情**
- 封面背景 + 完整信息表（编号 / 发售日 / 时长 / 语言版本 / 榜单名次）
- 标签、声优、评分分布、评论列表
- 曲目树（支持多层目录结构）与逐曲播放
- 同社团作品横滑区

**播放器**
- 后台播放与通知栏控制（`just_audio` + `just_audio_background`）
- 播放队列管理（跳转、移除、清空）
- 倍速 0.5x ~ 2.0x、单曲/列表循环、随机播放
- 定时关闭（15/30/45/60/90 分钟）
- 低音质模式（省流量）
- 收听进度自动保存，可续播
- 从封面提取主色作为动态主题色（可选）

**资料库（全部离线可用）**
- 收藏夹、收听历史（SQLite 持久化）
- 本地播放列表
- 离线下载：整个作品的曲目串行下载、进度展示、失败重试、体积统计、本地播放
- 云端播放列表（登录后）：新建、加入、移出、查看

**其它**
- 账号登录 / 注册
- 三语界面（简体中文 / 日本語 / English）
- 浅色 / 深色 / 跟随系统，8 种强调色
- 成人封面默认打码，点击可揭开
- 接口线路手动指定或自动切换
- 搜索历史、作品分享、跳转 DLsite 原始页面

---

## 三、目录结构

```
lib/
├── main.dart                     入口：后台播放初始化、依赖装配
├── app.dart                      MaterialApp、主题、迷你播放器浮层
├── core/
│   ├── api/api_client.dart       线路故障转移、鉴权、媒体地址解析
│   ├── models/                   Work / TrackNode / Tag / Review / Playlist …
│   ├── storage/app_prefs.dart    偏好设置（shared_preferences）
│   ├── storage/library_db.dart   收藏 / 历史 / 下载 / 进度（sqflite）
│   ├── theme/app_theme.dart      Material 3 明暗主题与装饰
│   ├── data/tag_catalog.dart     内置标签目录（生成）
│   ├── data/featured_tags.dart   首页精选标签
│   └── utils/formatters.dart     时长 / 计数 / 价格 / 体积格式化
├── l10n/app_localizations.dart   三语字典与 Delegate
├── state/                        SettingsState / AuthState / LibraryState /
│                                 PlayerState / DownloadState / WorkFeed
├── widgets/                      CoverImage / WorkCard / WorkRail / MiniPlayer …
└── screens/                      首页 / 浏览 / 搜索 / 详情 / 播放器 / 我的 / 设置 …
```

---

## 四、构建

### 环境要求

| 组件 | 版本 |
| --- | --- |
| Flutter | 3.47.x（stable） |
| Dart | 3.13（随 Flutter 附带） |
| JDK | 17 ~ 21 |
| Android SDK | build-tools 34+，platform 36 |

> 仓库不包含 `android/local.properties`（内含本机 SDK 路径）。
> 首次执行 `flutter build` / `flutter run` 时 Flutter 会自动生成，无需手动创建。
>
> Gradle wrapper（`gradlew`、`gradlew.bat`、`gradle-wrapper.jar`）按 Flutter 官方模板约定不纳入版本控制，
> 同样由 Flutter 工具链自动补齐；`gradle/wrapper/gradle-wrapper.properties` 已提交，用于锁定 Gradle 版本。

### 构建与检查

```bash
flutter pub get
flutter analyze          # 静态检查（当前 0 issue）
flutter test             # 数据契约与格式化单元测试
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk（约 56 MB）
```

如需按 ABI 拆分减小体积：

```bash
flutter build apk --release --split-per-abi
```

### Android 入口与签名

* 承载界面的 Activity 是 `com.ryanheise.audioservice.AudioServiceActivity`
  （`audio_service` 的要求，它继承自 `FlutterActivity`），在 `AndroidManifest.xml` 中注册为 LAUNCHER。
* `com.asmrone.asmr_one.MainActivity` 是 `flutter create` 生成的默认入口，当前未被清单引用，
  保留以便直接用 IDE 的默认运行配置调试。
* `release` 构建沿用 Flutter 模板的 debug 签名，**仅供本机测试安装，不可用于分发**。
  正式发布请自行生成 keystore 并配置 `android/key.properties`（该文件已被忽略）。

### 重新生成内置标签目录

```bash
python tool/gen_tags.py          # 扫描作品列表 -> tool/tags_raw.json
python tool/gen_tag_catalog.py   # tags_raw.json -> lib/core/data/tag_catalog.dart
```

---

## 五、已知限制

* 云端播放列表的「列表接口」在官网前端经过多次调整，`fetchMyPlaylists()`
  会依次尝试几个候选路径；全部不可用时界面会退化为只显示本地列表，
  不影响其它功能。
* 评论、推荐等接口需要登录；未登录时相应区块不展示。
* 音频下载依赖带 token 的接口地址，付费作品需先登录。
* 仅适配 Android，未包含 iOS / 桌面端工程。
