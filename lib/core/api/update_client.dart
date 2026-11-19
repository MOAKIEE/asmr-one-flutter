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

/// 基于 GitHub Releases API 的更新检查客户端。
class UpdateClient {
  UpdateClient({
    HttpClientAdapter? adapter,
    this.endpoint = AppInfo.latestReleaseApiUrl,
  }) {
    if (adapter != null) _dio.httpClientAdapter = adapter;
  }

  final String endpoint;

  late final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 10),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': AppInfo.repoName,
      },
      validateStatus: (code) => code != null && code >= 200 && code < 500,
    ),
  );

  /// 拉取最新正式 Release；仓库尚无正式 Release（HTTP 404）时返回 `null`。
  Future<ReleaseInfo?> fetchLatestRelease() async {
    try {
      final res = await _dio.get<dynamic>(
        endpoint,
        options: Options(responseType: ResponseType.json),
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
