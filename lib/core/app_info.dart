import 'package:package_info_plus/package_info_plus.dart';

/// 应用元数据与仓库常量。
class AppInfo {
  const AppInfo._();

  /// 平台插件不可用时的版本回退值（与 pubspec.yaml 保持同步）。
  static const String fallbackVersion = '1.2.0';

  static const String repoOwner = 'MOAKIEE';
  static const String repoName = 'asmr-one-flutter';
  static const String repoSlug = '$repoOwner/$repoName';
  static const String repoDisplayUrl = 'github.com/$repoSlug';
  static const String repoUrl = 'https://github.com/$repoSlug';
  static const String releasesUrl = '$repoUrl/releases';
  static const String latestReleaseApiUrl =
      'https://api.github.com/repos/$repoSlug/releases/latest';

  /// 读取当前安装包版本号，平台插件不可用时回退到 [fallbackVersion]。
  static Future<String> resolveVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final v = info.version.trim();
      return v.isEmpty ? fallbackVersion : v;
    } catch (_) {
      return fallbackVersion;
    }
  }
}
