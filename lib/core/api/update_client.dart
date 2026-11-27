import 'dart:convert';

import 'package:dio/dio.dart';

import '../app_info.dart';
import '../models/common.dart';
import '../models/release.dart';

/// 更新检查失败分类，由界面层按当前语言展示文案。
enum UpdateErrorKind { network, rateLimited, invalidResponse, unknown }

/// 检查更新异常。
class UpdateCheckException implements Exception {
  const UpdateCheckException(
    this.kind, {
    this.statusCode,
    this.detail,
  });

  final UpdateErrorKind kind;
  final int? statusCode;
  final String? detail;

  @override
  String toString() =>
      'UpdateCheckException($kind, statusCode: $statusCode, detail: $detail)';
}

/// 更新检查客户端：
/// 1. 优先拉取 Release 静态清单 `latest.json`（走下载 CDN，不消耗 GitHub API 配额）；
/// 2. 清单缺失或不可用时回退至 GitHub Releases API；
/// 3. API 触发限流（403/429）时再降级解析 `releases/latest` 302 跳转标签。
class UpdateClient {
  UpdateClient({
    HttpClientAdapter? adapter,
    this.manifestEndpoint = AppInfo.latestReleaseManifestUrl,
    this.endpoint = AppInfo.latestReleaseApiUrl,
    this.redirectEndpoint = AppInfo.latestReleaseRedirectUrl,
  }) {
    if (adapter != null) _dio.httpClientAdapter = adapter;
  }

  /// 静态 `latest.json` 地址；传 `null` 可跳过静态清单直接走 API。
  final String? manifestEndpoint;

  /// GitHub Releases API 地址。
  final String endpoint;

  /// `releases/latest` 跳转地址，用于 API 限流兜底；传 `null` 可禁用。
  final String? redirectEndpoint;

  late final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 10),
      headers: const {'User-Agent': AppInfo.repoName},
      validateStatus: (code) => code != null && code >= 200 && code < 500,
    ),
  );

  static const Map<String, String> _apiHeaders = {
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  /// 拉取最新正式 Release；仓库尚无正式 Release（HTTP 404）时返回 `null`。
  Future<ReleaseInfo?> fetchLatestRelease() async {
    final manifestUrl = manifestEndpoint;
    if (manifestUrl != null && manifestUrl.isNotEmpty) {
      final manifestResult = await _tryFetchManifest(manifestUrl);
      if (manifestResult.resolved) return manifestResult.release;
    }

    try {
      return await _fetchFromApi();
    } on UpdateCheckException catch (e) {
      if (e.kind == UpdateErrorKind.rateLimited) {
        final redirectUrl = redirectEndpoint;
        if (redirectUrl != null && redirectUrl.isNotEmpty) {
          final fallback = await _tryFetchFromRedirect(redirectUrl);
          if (fallback != null) return fallback;
        }
      }
      rethrow;
    }
  }

  /// 尝试拉取静态 `latest.json`。
  ///
  /// 仅网络连接异常直接抛出；HTTP 404 / 限流 / 格式异常均交由后续来源回退。
  Future<({bool resolved, ReleaseInfo? release})> _tryFetchManifest(
    String url,
  ) async {
    try {
      final res = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: const {'Accept': 'application/json, */*'},
        ),
      );
      final code = res.statusCode ?? 0;
      if (code < 200 || code >= 300) {
        return (resolved: false, release: null);
      }
      final raw = res.data;
      if (raw == null || raw.trim().isEmpty) {
        return (resolved: false, release: null);
      }
      final decoded = jsonDecode(raw);
      final map = asMap(decoded);
      if (map.isEmpty) return (resolved: false, release: null);
      if (asBool(map['draft'])) return (resolved: true, release: null);
      final release = ReleaseInfo.tryFromJson(map);
      if (release == null) return (resolved: false, release: null);
      return (resolved: true, release: release);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.badResponse) {
        return (resolved: false, release: null);
      }
      throw UpdateCheckException(
        UpdateErrorKind.network,
        statusCode: e.response?.statusCode,
        detail: e.message,
      );
    } on FormatException {
      return (resolved: false, release: null);
    } catch (_) {
      return (resolved: false, release: null);
    }
  }

  Future<ReleaseInfo?> _fetchFromApi() async {
    try {
      final res = await _dio.get<dynamic>(
        endpoint,
        options: Options(
          responseType: ResponseType.json,
          headers: _apiHeaders,
        ),
      );
      final code = res.statusCode ?? 0;
      if (code == 404) return null;

      if (code == 429 || _isRateLimited(res)) {
        throw UpdateCheckException(
          UpdateErrorKind.rateLimited,
          statusCode: code,
          detail: _extractMessage(res.data),
        );
      }

      if (code < 200 || code >= 300) {
        throw UpdateCheckException(
          UpdateErrorKind.unknown,
          statusCode: code,
          detail: _extractMessage(res.data),
        );
      }

      final map = asMap(res.data);
      if (map.isEmpty) {
        throw const UpdateCheckException(UpdateErrorKind.invalidResponse);
      }
      if (asBool(map['draft'])) return null;

      final release = ReleaseInfo.tryFromJson(map);
      if (release == null) {
        throw const UpdateCheckException(UpdateErrorKind.invalidResponse);
      }
      return release;
    } on UpdateCheckException {
      rethrow;
    } on DioException catch (e) {
      final res = e.response;
      final code = res?.statusCode;
      if (code == 429 || (res != null && _isRateLimited(res))) {
        throw UpdateCheckException(
          UpdateErrorKind.rateLimited,
          statusCode: code,
          detail: _extractMessage(res?.data),
        );
      }
      if (e.type == DioExceptionType.badResponse && code != null) {
        throw UpdateCheckException(
          UpdateErrorKind.unknown,
          statusCode: code,
          detail: _extractMessage(res?.data),
        );
      }
      throw UpdateCheckException(
        UpdateErrorKind.network,
        statusCode: code,
        detail: e.message,
      );
    } catch (e) {
      throw UpdateCheckException(
        UpdateErrorKind.unknown,
        detail: e.toString(),
      );
    }
  }

  /// 通过 `releases/latest` 的 302 Location 跳转提取最新正式版本标签。
  Future<ReleaseInfo?> _tryFetchFromRedirect(String url) async {
    try {
      final res = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: false,
          validateStatus: (code) => code != null && code >= 200 && code < 400,
        ),
      );
      final location = res.headers.value('location')?.trim();
      if (location == null || location.isEmpty) return null;

      final resolvedUri = Uri.tryParse(url)?.resolve(location);
      if (resolvedUri == null) return null;
      final safeUrl = sanitizeGitHubUrl(resolvedUri.toString());
      if (safeUrl == null) return null;

      final segments = resolvedUri.pathSegments;
      final tagIdx = segments.indexOf('tag');
      if (tagIdx < 0 || tagIdx + 1 >= segments.length) return null;

      final rawTag = Uri.decodeComponent(segments[tagIdx + 1]).trim();
      if (rawTag.isEmpty || AppVersion.tryParse(rawTag) == null) return null;

      return ReleaseInfo(
        tagName: rawTag,
        name: rawTag,
        body: '',
        htmlUrl: safeUrl,
      );
    } catch (_) {
      return null;
    }
  }

  bool _isRateLimited(Response<dynamic> res) {
    final code = res.statusCode;
    if (code != 403 && code != 429) return false;
    final remaining = res.headers.value('x-ratelimit-remaining');
    if (remaining == '0') return true;
    final message = (_extractMessage(res.data) ?? '').toLowerCase();
    return message.contains('rate limit');
  }

  String? _extractMessage(dynamic data) => asStringOrNull(asMap(data)['message']);
}
