import '../app_info.dart';
import 'common.dart';

/// 语义化版本号解析与比较（兼容前导 `v`、省略补丁位、预发布段与 `+build` 元数据）。
class AppVersion implements Comparable<AppVersion> {
  const AppVersion({
    required this.core,
    this.preRelease = const [],
  });

  final List<int> core;
  final List<String> preRelease;

  static final RegExp _digitsOnly = RegExp(r'^\d+$');
  static final RegExp _preReleaseId = RegExp(r'^[0-9A-Za-z-]+$');

  static AppVersion? tryParse(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('v') || s.startsWith('V')) {
      s = s.substring(1).trim();
    }
    if (s.isEmpty) return null;

    // 剥离 build metadata（如 1.2.0+3）。
    final plusIndex = s.indexOf('+');
    if (plusIndex >= 0) {
      s = s.substring(0, plusIndex);
    }
    if (s.isEmpty) return null;

    var corePart = s;
    var preParts = const <String>[];
    final dashIndex = s.indexOf('-');
    if (dashIndex >= 0) {
      corePart = s.substring(0, dashIndex);
      final preRaw = s.substring(dashIndex + 1);
      if (preRaw.isEmpty) return null;
      final split = preRaw.split('.');
      for (final seg in split) {
        if (seg.isEmpty || !_preReleaseId.hasMatch(seg)) return null;
      }
      preParts = List<String>.unmodifiable(split);
    }

    final coreSegments = corePart.split('.');
    if (coreSegments.isEmpty) return null;
    final parsedCore = <int>[];
    for (final seg in coreSegments) {
      if (seg.isEmpty || !_digitsOnly.hasMatch(seg)) return null;
      final n = int.tryParse(seg);
      if (n == null) return null;
      parsedCore.add(n);
    }

    return AppVersion(
      core: List<int>.unmodifiable(parsedCore),
      preRelease: preParts,
    );
  }

  /// 判断 [latest] 是否严格高于 [current]。任一版本无法解析时返回 `false`。
  static bool isNewer({
    required String latest,
    required String current,
  }) {
    final latestVer = tryParse(latest);
    final currentVer = tryParse(current);
    if (latestVer == null || currentVer == null) return false;
    return latestVer.compareTo(currentVer) > 0;
  }

  /// 标准化展示版本号（不含前导 `v` 与 `+build`）。
  static String normalizeLabel(String raw) {
    final parsed = tryParse(raw);
    if (parsed != null) return parsed.toString();
    var s = raw.trim();
    if (s.startsWith('v') || s.startsWith('V')) {
      s = s.substring(1).trim();
    }
    return s;
  }

  @override
  int compareTo(AppVersion other) {
    final maxLen = core.length > other.core.length
        ? core.length
        : other.core.length;
    for (var i = 0; i < maxLen; i++) {
      final a = i < core.length ? core[i] : 0;
      final b = i < other.core.length ? other.core[i] : 0;
      if (a != b) return a.compareTo(b);
    }

    if (preRelease.isEmpty && other.preRelease.isEmpty) return 0;
    if (preRelease.isEmpty) return 1;
    if (other.preRelease.isEmpty) return -1;

    final minPre = preRelease.length < other.preRelease.length
        ? preRelease.length
        : other.preRelease.length;
    for (var i = 0; i < minPre; i++) {
      final a = preRelease[i];
      final b = other.preRelease[i];
      if (a == b) continue;
      final aNum = _digitsOnly.hasMatch(a) ? int.tryParse(a) : null;
      final bNum = _digitsOnly.hasMatch(b) ? int.tryParse(b) : null;
      if (aNum != null && bNum != null) return aNum.compareTo(bNum);
      if (aNum != null) return -1;
      if (bNum != null) return 1;
      return a.compareTo(b);
    }
    return preRelease.length.compareTo(other.preRelease.length);
  }

  @override
  String toString() {
    final base = core.join('.');
    return preRelease.isEmpty ? base : '$base-${preRelease.join('.')}';
  }
}

/// 校验并返回可信的 GitHub HTTPS 链接。
String? sanitizeGitHubUrl(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) {
    return null;
  }
  final host = uri.host.toLowerCase();
  if (host.isEmpty) return null;
  final allowed =
      host == 'github.com' ||
      host.endsWith('.github.com') ||
      host.endsWith('.githubusercontent.com');
  return allowed ? uri.toString() : null;
}

/// GitHub Release 附带的下载资产。
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.size,
    required this.downloadUrl,
  });

  final String name;
  final int size;
  final String downloadUrl;

  bool get isApk => name.toLowerCase().endsWith('.apk');

  /// 大多数现代 Android 设备优先推荐 `arm64-v8a` 分包。
  bool get isRecommendedApk =>
      isApk && name.toLowerCase().contains('arm64-v8a');

  static ReleaseAsset? tryFromJson(Map<String, dynamic> json) {
    final name = asString(json['name']).trim();
    final url = sanitizeGitHubUrl(asStringOrNull(json['browser_download_url']));
    if (name.isEmpty || url == null) return null;
    return ReleaseAsset(
      name: name,
      size: asInt(json['size']),
      downloadUrl: url,
    );
  }
}

/// GitHub Release 元信息。
class ReleaseInfo {
  const ReleaseInfo({
    required this.tagName,
    required this.name,
    required this.body,
    required this.htmlUrl,
    this.publishedAt,
    this.prerelease = false,
    this.assets = const [],
  });

  final String tagName;
  final String name;
  final String body;
  final String htmlUrl;
  final DateTime? publishedAt;
  final bool prerelease;
  final List<ReleaseAsset> assets;

  /// 供界面展示的版本标签，统一以 `v` 开头（如 `v1.3.0`）。
  String get versionTag {
    final normalized = AppVersion.normalizeLabel(tagName);
    if (normalized.isEmpty) return tagName.trim();
    return 'v$normalized';
  }

  /// 按推荐顺序排列的 APK 安装包资产列表。
  List<ReleaseAsset> get apkAssets {
    final list = assets.where((a) => a.isApk).toList();
    list.sort((a, b) {
      final pa = _apkPriority(a.name);
      final pb = _apkPriority(b.name);
      if (pa != pb) return pa.compareTo(pb);
      return a.name.compareTo(b.name);
    });
    return List<ReleaseAsset>.unmodifiable(list);
  }

  static int _apkPriority(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.contains('arm64-v8a')) return 0;
    if (!lower.contains('armeabi') &&
        !lower.contains('x86') &&
        !lower.contains('mips')) {
      return 1;
    }
    if (lower.contains('armeabi-v7a')) return 2;
    if (lower.contains('x86_64')) return 3;
    return 4;
  }

  static ReleaseInfo? tryFromJson(Map<String, dynamic> json) {
    if (asBool(json['draft'])) return null;
    final tagName = asString(json['tag_name']).trim();
    if (tagName.isEmpty || AppVersion.tryParse(tagName) == null) return null;

    final rawAssets = asMapList(json['assets']);
    final assets = <ReleaseAsset>[];
    for (final entry in rawAssets) {
      final asset = ReleaseAsset.tryFromJson(entry);
      if (asset != null) assets.add(asset);
    }

    final publishedRaw = asStringOrNull(json['published_at']);
    return ReleaseInfo(
      tagName: tagName,
      name: asString(json['name'], tagName).trim(),
      body: asString(json['body']).trim(),
      htmlUrl:
          sanitizeGitHubUrl(asStringOrNull(json['html_url'])) ??
          AppInfo.releasesUrl,
      publishedAt: publishedRaw == null
          ? null
          : DateTime.tryParse(publishedRaw),
      prerelease: asBool(json['prerelease']),
      assets: List<ReleaseAsset>.unmodifiable(assets),
    );
  }
}
