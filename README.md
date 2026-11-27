# Mimori · Flutter 客户端

基于 [asmr.one](https://asmr.one) 公开接口实现的第三方 Android 客户端。

![Flutter](https://img.shields.io/badge/Flutter-3.47-02569B?logo=flutter&logoColor=white)
![Platform](https://img.shields.io/badge/platform-Android-3DDC84?logo=android&logoColor=white)
![Dart](https://img.shields.io/badge/Dart-3.13-0175C2?logo=dart&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-green)

> [!IMPORTANT]
> **非官方项目**：与 asmr.one 及 DLsite 无任何隶属关系。作品数据、封面与音频均来自其公开接口，
> 本项目不存储、不分发任何受版权保护的内容，仅用于 Flutter 客户端开发的学习与交流，请勿用于商业用途。
>
> **内容提示**：目标站点含成人向内容。应用内置内容分级筛选与封面打码开关，未满 18 岁请勿使用，
> 并请遵守你所在地区的相关法律法规。

## 功能

- **浏览发现** — 首页五个榜单横滑区、条件筛选（标签 / 评分 / 时长 / 字幕 / 翻译版 / 分级）、
  关键词搜索、标签浏览，网格与列表双布局
- **作品详情** — 信息表、标签、声优、评分分布、评论、多层曲目树、同社团作品
- **播放器** — 后台播放与通知栏控制、队列管理、0.5x~2x 倍速、循环与随机、A–B 片段循环、
  同步字幕（LRC / SRT / VTT）与时间点书签、定时关闭（睡眠音量渐弱 / 播完本曲停止）、
  低音质省流量、进度自动续播、重启恢复队列（不自动播放）
- **资料库（离线可用）** — 收藏、收听历史、本地播放列表、JSON 备份与合并恢复、
  整部作品离线下载（暂停 / 续传 / 重启恢复 / 仅 Wi-Fi / 体积统计）
- **云端** — 登录后可管理云端播放列表，并解锁完整标签库与付费作品音频
- **界面** — 三语（中 / 日 / 英）、明暗主题与 8 种强调色、封面取色、悬浮迷你播放器、应用内检查更新

## 构建

需要 Flutter 3.47+、JDK 17~21、Android SDK（platform 36 / build-tools 34+）。

```bash
flutter pub get
flutter analyze                       # 静态检查，当前 0 issue
flutter test                          # 数据契约与格式化单元测试
flutter build apk --debug             # 本机调试包（debug 签名）
flutter build apk --release           # 正式发布包（需配置签名，产物约 56 MB）
```

> `release` 构建强制从 `android/key.properties` 读取正式签名配置，缺少密钥配置或 keystore 文件时会直接报错，不会回退到 debug 签名。
>
> `android/key.properties` 示例（已加入 `.gitignore`，切勿提交）：
>
> ```properties
> storeFile=upload-keystore.jks
> storePassword=你的仓库密码
> keyAlias=upload
> keyPassword=你的密钥密码
> ```

## 项目结构

```
lib/
├── main.dart / app.dart      入口、主题装配、迷你播放器浮层
├── core/                     API 客户端、数据模型、本地存储、主题、工具
├── l10n/                     三语字典与 Delegate
├── state/                    ChangeNotifier：设置 / 登录 / 资料库 / 播放器 / 下载 / 分页列表
├── widgets/                  封面、作品卡片、横滑区、迷你播放器等通用组件
└── screens/                  首页 / 浏览 / 搜索 / 详情 / 播放器 / 我的 / 设置
```

接口层实现在 `lib/core/api/api_client.dart`，`tool/` 下的脚本用于重新生成内置标签目录
（未登录时接口不返回标签，故随包内置了一份热门标签）。

## 已知限制

- 仅适配 Android，未包含 iOS 与桌面端工程。
- 评论、推荐等接口需要登录，未登录时相应区块不展示。
- 云端播放列表接口在官网调整过多次，候选路径全部不可用时界面会退化为只展示本地列表。

## 许可

本项目基于 [MIT License](LICENSE) 开源。
