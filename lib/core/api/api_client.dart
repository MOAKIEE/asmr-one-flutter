import 'dart:async';

import 'package:dio/dio.dart';

import '../models/common.dart';
import '../models/playlist.dart';
import '../models/review.dart';
import '../models/track.dart';
import '../models/user.dart';
import '../models/work.dart';
import '../storage/app_prefs.dart';

/// 统一的 API 异常，携带可展示的文案。
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.rawError});

  final String message;
  final int? statusCode;
  final String? rawError;

  bool get isAuthError =>
      statusCode == 401 ||
      (rawError ?? '').toLowerCase().contains('authorization token');

  @override
  String toString() => message;
}

/// asmr.one 后端客户端。
///
/// 站点前端会在多个镜像线路间切换（`api.asmr.one` / `api.asmr-100.com` …），
/// 这里同样实现了自动故障转移：某个线路连接失败时按顺序尝试下一个。
class ApiClient {
  ApiClient._();

  static final ApiClient instance = ApiClient._();

  /// 可用线路。官网同款顺序。
  static const List<String> baseUrls = [
    'https://api.asmr.one',
    'https://api.asmr-100.com',
    'https://api.asmr-200.com',
    'https://api.asmr-300.com',
  ];

  /// 网站主域，用于生成 Referer 与分享链接。
  static const String siteUrl = 'https://asmr.one';

  late final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 15),
      headers: const {
        'User-Agent': 'ASMROneClient/1.0 (Flutter; Android)',
        'Accept': 'application/json',
      },
      // 交由业务层统一判断状态码，避免非 2xx 直接抛裸异常。
      validateStatus: (code) => code != null && code >= 200 && code < 400,
    ),
  );

  int _baseIndex = 0;

  /// 用户在设置里指定的线路；`null` 表示自动选择。
  int? preferredIndex;

  AppPrefs? _prefs;

  /// 由 [AuthState] 在启动时注入，用于读取登录态 token。
  void attachPrefs(AppPrefs prefs) {
    _prefs = prefs;
    if (prefs.autoSelectLine) {
      preferredIndex = null;
    } else {
      preferredIndex = prefs.preferredLineIndex;
    }
  }

  String? get token => _prefs?.token;

  bool get hasToken => (token ?? '').isNotEmpty;

  /// 当前生效的线路地址。
  String get baseUrl => baseUrls[_baseIndex % baseUrls.length];

  String get baseUrlHost => Uri.parse(baseUrl).host;

  // ---------------------------------------------------------------------------
  // 底层请求：自动换线路重试
  // ---------------------------------------------------------------------------

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
    bool auth = false,
    int maxAttempts = 3,
  }) async {
    Object? lastError;
    final startIndex = preferredIndex ?? _baseIndex;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final index = (startIndex + attempt) % baseUrls.length;
      _baseIndex = index;
      final url = '${baseUrls[index]}$path';
      final t = token;
      try {
        final res = await _dio.request<dynamic>(
          url,
          data: body,
          queryParameters: query,
          options: Options(
            method: method,
            headers: {
              if (auth && t != null && t.isNotEmpty)
                'Authorization': 'Bearer $t',
              'Referer': '$siteUrl/',
            },
            responseType: ResponseType.json,
          ),
        );
        return _unwrap(res);
      } on DioException catch (e) {
        lastError = e;
        if ((method == 'GET' || method == 'HEAD') &&
            _isRetryable(e) &&
            attempt < maxAttempts - 1) {
          continue; // 换下一条线路
        }
        throw _mapDioError(e);
      }
    }
    throw ApiException('网络请求失败，请检查网络连接后再试。', rawError: lastError?.toString());
  }

  bool _isRetryable(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.unknown:
        return true;
      default:
        // 5xx / 502 / 521 之类的网关错误也值得换线路。
        final code = e.response?.statusCode ?? 0;
        return code >= 500;
    }
  }

  dynamic _unwrap(Response<dynamic> res) {
    final code = res.statusCode ?? 0;
    final data = res.data;
    if (code >= 200 && code < 300) return data;

    final map = asMap(data);
    final rawError = asStringOrNull(map['error']);
    throw ApiException(
      _humanize(rawError) ?? '请求失败（HTTP $code）',
      statusCode: code,
      rawError: rawError,
    );
  }

  ApiException _mapDioError(DioException e) {
    final map = asMap(e.response?.data);
    final rawError = asStringOrNull(map['error']);
    final code = e.response?.statusCode;
    final msg =
        _humanize(rawError) ??
        switch (e.type) {
          DioExceptionType.connectionTimeout ||
          DioExceptionType.sendTimeout ||
          DioExceptionType.receiveTimeout => '连接超时，请稍后重试。',
          DioExceptionType.connectionError => '无法连接到服务器，请检查网络或切换线路。',
          DioExceptionType.cancel => '请求已取消。',
          _ => '网络异常：${e.message ?? '未知错误'}',
        };
    return ApiException(msg, statusCode: code, rawError: rawError);
  }

  String? _humanize(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final lower = raw.toLowerCase();
    if (lower.contains('authorization token') || lower.contains('jwt')) {
      return '需要登录后才能使用该功能，请先在「我的」中登录账号。';
    }
    if (lower.contains('unauthorized')) return '登录状态已过期，请重新登录。';
    if (lower.contains('not found')) return '内容不存在或已被删除。';
    if (lower.contains('too many')) return '请求过于频繁，请稍后再试。';
    return raw;
  }

  Future<dynamic> _get(
    String path, {
    Map<String, dynamic>? query,
    bool auth = false,
  }) => _request('GET', path, query: query, auth: auth);

  Future<dynamic> _post(
    String path, {
    Object? body,
    Map<String, dynamic>? query,
    bool auth = true,
  }) => _request('POST', path, body: body, query: query, auth: auth);

  // ---------------------------------------------------------------------------
  // 作品
  // ---------------------------------------------------------------------------

  /// 作品列表 / 条件筛选。
  Future<WorksPage> fetchWorks(WorkQuery query) async {
    final data = await _get('/api/works', query: query.toQueryParameters());
    return WorksPage.fromJson(asMap(data));
  }

  /// 随机的「随便听听」，走 random 排序 + 首页偏移。
  Future<Work?> randomWork({bool? nsfw, int? seed}) async {
    final page = seed ?? DateTime.now().millisecondsSinceEpoch % 200 + 1;
    final data = await _get(
      '/api/works',
      query: {
        'page': page,
        'pageSize': 1,
        'order': 'random',
        'sort': 'desc',
        if (nsfw != null) 'nsfw': nsfw ? 'true' : 'false',
      },
    );
    final list = asMapList(asMap(data)['works']);
    return list.isEmpty ? null : Work.fromJson(list.first);
  }

  Future<Work> fetchWork(int id) async {
    final data = await _get('/api/work/$id');
    final map = asMap(data);
    if (map.isEmpty) throw ApiException('作品详情为空，可能已被删除。');
    return Work.fromJson(map);
  }

  /// 同名详情接口的备用路径，部分线路只挂了其中一个。
  Future<Work> fetchWorkInfo(int id) async {
    final data = await _get('/api/workInfo/$id');
    final map = asMap(data);
    if (map.isEmpty) throw ApiException('作品详情为空，可能已被删除。');
    return Work.fromJson(map);
  }

  Future<List<TrackNode>> fetchTracks(int workId) async {
    final data = await _get('/api/tracks/$workId');
    if (data is List) {
      return asMapList(data).map(TrackNode.fromJson).toList();
    }
    // 少数线路把曲目包在 `{tracks: [...]}` 里。
    return asMapList(asMap(data)['tracks']).map(TrackNode.fromJson).toList();
  }

  /// 关键词搜索。
  Future<WorksPage> search(
    String keyword, {
    int page = 1,
    int pageSize = 20,
    WorkOrder order = WorkOrder.createDate,
    SortDirection sort = SortDirection.desc,
    List<int> tags = const [],
    double? rate,
    int? duration,
    bool? subtitle,
    bool? nsfw,
  }) async {
    if (keyword.trim().isEmpty) return WorksPage.empty;
    final data = await _get(
      '/api/search/${Uri.encodeComponent(keyword.trim())}',
      query: {
        'page': page,
        'pageSize': pageSize,
        'order': order.value,
        'sort': sort.value,
        if (tags.isNotEmpty) 'tags': tags.join(','),
        'rate': ?rate,
        'duration': ?duration,
        if (subtitle == true) 'subtitle': 1,
        if (nsfw != null) 'nsfw': nsfw ? 'true' : 'false',
      },
    );
    return WorksPage.fromJson(asMap(data));
  }

  // ---------------------------------------------------------------------------
  // 账号
  // ---------------------------------------------------------------------------

  Future<SessionInfo> fetchSession() async {
    final data = await _get('/api/auth/me', auth: true);
    return SessionInfo.fromJson(asMap(data));
  }

  /// 登录成功返回 JWT。
  Future<String> login(String name, String password) async {
    final data = await _post(
      '/api/login',
      body: {'name': name, 'password': password},
      auth: false,
    );
    final map = asMap(data);
    final t =
        asStringOrNull(map['token']) ??
        asStringOrNull(asMap(map['user'])['token']);
    if (t == null || t.isEmpty) throw ApiException('登录失败：服务端未返回令牌。');
    return t;
  }

  Future<void> register(
    String name,
    String password, {
    String? recommenderUuid,
  }) async {
    await _post(
      '/api/auth/reg',
      body: {
        'name': name,
        'password': password,
        'recommenderUuid': ?recommenderUuid,
      },
      auth: false,
    );
  }

  // ---------------------------------------------------------------------------
  // 标签 / 评论 / 投票
  // ---------------------------------------------------------------------------

  /// 全量标签目录（需要登录）。
  Future<List<Tag>> fetchTags({int page = 1, int pageSize = 500}) async {
    final data = await _get(
      '/api/tags',
      query: {'page': page, 'pageSize': pageSize},
      auth: true,
    );
    if (data is List) return asMapList(data).map(Tag.fromJson).toList();
    final map = asMap(data);
    final raw = map['tags'] ?? map['data'] ?? const [];
    return asMapList(raw).map(Tag.fromJson).toList();
  }

  Future<ReviewPage> fetchReviews(
    int workId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final data = await _get(
      '/api/review',
      query: {'workId': workId, 'page': page, 'pageSize': pageSize},
      auth: true,
    );
    return ReviewPage.fromJson(asMap(data));
  }

  /// 提交 / 更新本人评分与评论。
  Future<void> submitReview({
    required int workId,
    required double rating,
    String? reviewText,
    String? progress,
  }) async {
    await _post(
      '/api/review',
      body: {
        'work_id': workId,
        'rating': rating,
        'review_text': reviewText ?? '',
        'progress': progress ?? '',
      },
    );
  }

  /// 给作品的标签投票（`vote` 为 1 赞 / -1 踩 / 0 取消）。
  Future<void> voteWorkTag(int workId, int tagId, int vote) async {
    await _post(
      '/api/vote/vote-work-tag',
      body: {'work_id': workId, 'tag_id': tagId, 'vote': vote},
    );
  }

  // ---------------------------------------------------------------------------
  // 播放列表
  // ---------------------------------------------------------------------------

  Future<List<Playlist>> fetchMyPlaylists({
    int page = 1,
    int pageSize = 100,
  }) async {
    // 该接口在官网前端是登录后加载的，路径在不同版本间出现过变化，
    // 因此按候选顺序尝试，全部失败时返回空列表由界面提示。
    final candidates = [
      '/api/playlist/my-playlists',
      '/api/me/playlists',
      '/api/playlists',
    ];
    ApiException? last;
    for (final path in candidates) {
      try {
        final data = await _get(
          path,
          query: {'page': page, 'pageSize': pageSize},
          auth: true,
        );
        final raw = data is List
            ? data
            : (asMap(data)['playlists'] ?? asMap(data)['data'] ?? const []);
        return asMapList(raw).map(Playlist.fromJson).toList();
      } on ApiException catch (e) {
        last = e;
        // 401 说明确实是有效路径但没登录，无需继续尝试其它候选。
        if (e.isAuthError) rethrow;
        continue;
      }
    }
    if (last != null && last.statusCode == 404) return const [];
    throw last ?? ApiException('无法获取播放列表。');
  }

  Future<PlaylistDetail> fetchPlaylistDetail(int id) async {
    final data = await _get(
      '/api/playlist/get-playlist-metadata',
      query: {'id': id},
      auth: true,
    );
    return PlaylistDetail.fromJson(asMap(data));
  }

  Future<Playlist?> fetchDefaultPlaylist() async {
    try {
      final data = await _get(
        '/api/playlist/get-default-mark-target-playlist',
        auth: true,
      );
      final map = asMap(data);
      if (map.isEmpty) return null;
      final raw = map['playlist'] ?? map;
      final playlist = Playlist.fromJson(asMap(raw));
      return playlist.id == 0 ? null : playlist;
    } on ApiException {
      return null;
    }
  }

  Future<Playlist> createPlaylist({
    required String name,
    String? description,
    String privacy = 'private',
  }) async {
    final data = await _post(
      '/api/playlist/create-playlist',
      body: {
        'name': name,
        'description': description ?? '',
        'privacy': privacy,
      },
    );
    final map = asMap(data);
    final raw = map['playlist'] ?? map;
    return Playlist.fromJson(asMap(raw));
  }

  /// 向播放列表加入作品，`works` 传作品的 DLsite 编号（如 `RJ01653004`）。
  Future<void> addWorksToPlaylist(int playlistId, List<String> works) async {
    await _post(
      '/api/playlist/add-works-to-playlist',
      body: {'id': playlistId, 'works': works},
    );
  }

  Future<void> removeWorksFromPlaylist(
    int playlistId,
    List<String> works,
  ) async {
    await _post(
      '/api/playlist/remove-works-from-playlist',
      body: {'id': playlistId, 'works': works},
    );
  }

  /// 查询作品是否已在某些播放列表里（用于「已收藏」状态）。
  Future<PlaylistMembership> fetchPlaylistMembership(int workId) async {
    try {
      final data = await _get(
        '/api/playlist/get-work-exist-status-in-my-playlists',
        query: {'workId': workId},
        auth: true,
      );
      return PlaylistMembership.fromJson(asMap(data));
    } on ApiException {
      return PlaylistMembership.none;
    }
  }

  Future<Paged<dynamic>> ping() async {
    await _get('/api/health');
    return Paged.empty();
  }

  // ---------------------------------------------------------------------------
  // 资源地址
  // ---------------------------------------------------------------------------

  /// 封面图。`type` 仅支持 `main` / `sam` / `240x240`。
  String coverUrl(int workId, {String type = 'main'}) =>
      '${baseUrls[_baseIndex]}/api/cover/$workId.jpg?type=$type';

  /// 带鉴权的流媒体地址（付费作品需要登录）。
  String mediaStreamUrl(String hash, {bool lowQuality = false}) {
    final t = token ?? '';
    final seg = lowQuality ? 'stream-low' : 'stream';
    return '${baseUrls[_baseIndex]}/api/media/$seg/$hash?token=$t';
  }

  /// 带鉴权的下载地址。
  String mediaDownloadUrl(String hash) {
    final t = token ?? '';
    return '${baseUrls[_baseIndex]}/api/media/download/$hash?token=$t';
  }

  /// 解析音频节点的可播放地址：
  /// 优先使用接口直接给出的 CDN 地址，缺失（付费作品）时回退到带 token 的接口地址。
  String? resolveStreamUrl(TrackNode node, {bool preferLowQuality = false}) {
    if (preferLowQuality && (node.streamLowQualityUrl ?? '').isNotEmpty) {
      return node.streamLowQualityUrl;
    }
    if ((node.mediaStreamUrl ?? '').isNotEmpty) return node.mediaStreamUrl;
    if (preferLowQuality && (node.hash ?? '').isNotEmpty) {
      return mediaStreamUrl(node.hash!, lowQuality: true);
    }
    if ((node.hash ?? '').isNotEmpty && hasToken) {
      return mediaStreamUrl(node.hash!);
    }
    return null;
  }

  String? resolveDownloadUrl(TrackNode node) {
    if ((node.mediaDownloadUrl ?? '').isNotEmpty) return node.mediaDownloadUrl;
    if ((node.hash ?? '').isNotEmpty && hasToken) {
      return mediaDownloadUrl(node.hash!);
    }
    return null;
  }

  /// 网站上的作品页面地址。
  String webUrl(Work work) => '$siteUrl/works/${work.id}';

  /// 直接下载二进制文件到本地（音频离线缓存使用）。
  ///
  /// 与普通接口不同，这里把响应体写入 [savePath]，并通过 [onProgress]
  /// 回报进度；失败时抛出 [ApiException]。
  Future<void> downloadRaw({
    required String url,
    required String savePath,
    CancelToken? cancelToken,
    void Function(int received, int total)? onProgress,
  }) async {
    try {
      await _dio.download(
        url,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: onProgress,
        options: Options(
          headers: {'Referer': '$siteUrl/'},
          responseType: ResponseType.stream,
        ),
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }
}
