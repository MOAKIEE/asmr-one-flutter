import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../core/data/tag_catalog.dart';
import '../core/models/common.dart';
import '../core/models/playlist.dart';
import '../core/models/user.dart';
import '../core/models/work.dart';
import '../core/storage/app_prefs.dart';
import '../core/storage/stream_audio_cache.dart';

/// 登录状态 + 依赖登录态的云端数据（播放列表、标签目录）。
class AuthState extends ChangeNotifier {
  AuthState(this._prefs, {ApiClient? api, this.onTokenChanged})
    : _api = api ?? ApiClient.instance {
    _api.attachPrefs(_prefs);
    _token = _prefs.token;
  }

  final AppPrefs _prefs;
  final ApiClient _api;
  final Future<void> Function()? onTokenChanged;

  String? _token;
  AppUser _user = AppUser.anonymous;
  bool _authEnabled = true;
  bool _regEnabled = true;
  bool _busy = false;
  String? _lastError;
  int _sessionVersion = 0;

  List<Playlist> _playlists = const [];
  bool _playlistsLoaded = false;
  List<Tag>? _serverTags;

  // --- 只读访问 ---
  bool get loggedIn => (_token ?? '').isNotEmpty && _user.loggedIn;
  bool get hasToken => (_token ?? '').isNotEmpty;
  AppUser get user => _user;
  int get sessionVersion => _sessionVersion;

  /// 区分游客与不同登录账号的会话标识（注销或切换账号时必然变化）。
  String get accountKey {
    final t = _token;
    if (t == null || t.isEmpty) return '';
    final uid = _user.id ?? '';
    final uname = _user.name ?? '';
    return '$_sessionVersion:$uid:$uname:$t';
  }

  /// 用于流媒体缓存隔离的稳定账号范围（不含明文令牌，令牌刷新后不变）。
  /// 令牌存在但账号身份尚未确认且无已持久化范围时返回 `null`，由播放器跳过账号缓存读写。
  String? get cacheAccountScope => StreamAudioCache.accountScopeFor(
    hasToken: hasToken,
    userId: _user.id,
    userName: _user.name,
    persistedScope: _prefs.accountScope,
  );
  bool get authEnabled => _authEnabled;
  bool get regEnabled => _regEnabled;
  bool get busy => _busy;
  String? get lastError => _lastError;
  List<Playlist> get playlists => _playlists;
  bool get playlistsLoaded => _playlistsLoaded;

  /// 标签目录：优先使用服务端完整目录，未登录时回退到内置热门标签。
  List<Tag> get tags => _serverTags ?? BundledTags.all;
  bool get usingBundledTags => _serverTags == null;

  List<Tag> searchTags(String keyword) {
    final k = keyword.trim().toLowerCase();
    final src = tags;
    if (k.isEmpty) return src;
    return src
        .where(
          (t) =>
              t.label(AppLang.zh).toLowerCase().contains(k) ||
              t.label(AppLang.ja).toLowerCase().contains(k) ||
              t.label(AppLang.en).toLowerCase().contains(k),
        )
        .toList();
  }

  /// 按 id 取标签展示名，找不到时回退为 `#id`。
  String tagLabel(int id, AppLang lang) {
    for (final t in tags) {
      if (t.id == id) return t.label(lang);
    }
    return '#$id';
  }

  /// 启动时校验本地 token 是否仍然有效。
  ///
  /// 网络异常时不清除 token（避免离线打开 App 就被登出）。
  Future<void> bootstrap() async {
    final version = _sessionVersion;
    final prevScope = cacheAccountScope;
    Future<void>? tokenRefresh;
    try {
      final session = await _api.fetchSession();
      if (version != _sessionVersion) return;
      _authEnabled = session.authEnabled;
      _regEnabled = session.regEnabled;
      if (session.user.loggedIn) {
        _user = session.user;
        _prefs.accountScope = StreamAudioCache.accountScopeFor(
          hasToken: hasToken,
          userId: _user.id,
          userName: _user.name,
        );
      } else if (!session.authEnabled && hasToken) {
        // 服务端关闭了登录，本地令牌已无意义。
        _user = AppUser.anonymous;
        _prefs.accountScope = null;
      } else {
        _user = AppUser.anonymous;
        if (!hasToken) _prefs.accountScope = null;
      }
    } on ApiException catch (e) {
      if (version != _sessionVersion) return;
      if (e.isAuthError) {
        _user = AppUser.anonymous;
        _prefs.accountScope = null;
        tokenRefresh = _setToken(null);
      }
      _lastError = e.message;
    } catch (_) {
      if (version != _sessionVersion) return;
      // 静默失败：保持本地状态，离线可用。
    }
    notifyListeners();
    if (tokenRefresh == null && prevScope != cacheAccountScope) {
      tokenRefresh = onTokenChanged?.call();
    }
    await tokenRefresh;
    if (loggedIn) _fireAndForget(_loadCloudData());
  }

  Future<bool> login(String name, String password) async {
    final version = ++_sessionVersion;
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      final t = await _api.login(name.trim(), password);
      if (version != _sessionVersion) return false;
      final session = await _api.fetchSession(sessionToken: t);
      if (version != _sessionVersion) return false;
      if (!session.user.loggedIn) throw ApiException('登录失败：服务端未确认登录状态。');
      // 校验期间其他请求仍属于原账号。
      final sessionVersion = ++_sessionVersion;
      _user = session.user;
      _prefs.accountScope = StreamAudioCache.accountScopeFor(
        hasToken: true,
        userId: _user.id,
        userName: _user.name,
      );
      _playlists = const [];
      _playlistsLoaded = false;
      _serverTags = null;
      _authEnabled = session.authEnabled;
      _regEnabled = session.regEnabled;
      final tokenRefresh = _setToken(t);
      notifyListeners();
      // 登录后异步补齐云端数据，不阻塞界面。
      _fireAndForget(_loadCloudData());
      try {
        await tokenRefresh;
      } finally {
        if (sessionVersion == _sessionVersion) {
          _busy = false;
          notifyListeners();
        }
      }
      return sessionVersion == _sessionVersion;
    } on ApiException catch (e) {
      if (version != _sessionVersion) return false;
      _lastError = e.message;
      _busy = false;
      notifyListeners();
      return false;
    } catch (e) {
      if (version != _sessionVersion) return false;
      _lastError = '$e';
      _busy = false;
      notifyListeners();
      return false;
    }
  }

  Future<String?> register(String name, String password) async {
    final version = _sessionVersion;
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      await _api.register(name.trim(), password);
      if (version != _sessionVersion) return null;
      _busy = false;
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      if (version != _sessionVersion) return e.message;
      _lastError = e.message;
      _busy = false;
      notifyListeners();
      return e.message;
    } catch (e) {
      if (version != _sessionVersion) return '$e';
      _lastError = '$e';
      _busy = false;
      notifyListeners();
      return '$e';
    }
  }

  Future<void> logout() async {
    _sessionVersion++;
    _user = AppUser.anonymous;
    _prefs.accountScope = null;
    _playlists = const [];
    _playlistsLoaded = false;
    _serverTags = null;
    _lastError = null;
    _busy = false;
    final tokenRefresh = _setToken(null);
    notifyListeners();
    await tokenRefresh;
  }

  Future<void>? _setToken(String? token) {
    if (_token == token) return null;
    _token = token;
    _prefs.token = token;
    return onTokenChanged?.call();
  }

  void clearError() {
    if (_lastError == null) return;
    _lastError = null;
    notifyListeners();
  }

  Future<void> _loadCloudData() async {
    await Future.wait([loadPlaylists(), loadServerTags()]);
  }

  /// 拉取服务端标签目录（需要登录）。
  Future<void> loadServerTags() async {
    final version = _sessionVersion;
    if (!hasToken) return;
    try {
      final list = await _api.fetchTags();
      if (version != _sessionVersion) return;
      if (list.isNotEmpty) {
        _serverTags = list;
        notifyListeners();
      }
    } catch (_) {
      // 失败则继续使用内置目录。
    }
  }

  Future<void> loadPlaylists({bool force = false}) async {
    final version = _sessionVersion;
    if (!hasToken) {
      _playlists = const [];
      _playlistsLoaded = true;
      notifyListeners();
      return;
    }
    if (_playlistsLoaded && !force) return;
    try {
      final list = await _api.fetchMyPlaylists();
      if (version != _sessionVersion) return;
      _playlists = list;
      _playlistsLoaded = true;
      _lastError = null;
    } on ApiException catch (e) {
      if (version != _sessionVersion) return;
      // 401 情况已在 ApiClient 里翻译成中文提示。
      if (e.statusCode == 404 || e.statusCode == 400) {
        _playlists = const [];
      }
      _lastError = e.statusCode == 404 ? null : e.message;
      _playlistsLoaded = true;
    } catch (_) {
      if (version != _sessionVersion) return;
      _playlistsLoaded = true;
    }
    notifyListeners();
  }

  Future<Playlist?> createPlaylist({
    required String name,
    String? description,
    String privacy = 'private',
  }) async {
    final version = _sessionVersion;
    try {
      final p = await _api.createPlaylist(
        name: name,
        description: description,
        privacy: privacy,
      );
      if (version != _sessionVersion) return null;
      _playlists = [p, ..._playlists];
      notifyListeners();
      return p;
    } on ApiException catch (e) {
      if (version != _sessionVersion) return null;
      _lastError = e.message;
      notifyListeners();
      return null;
    }
  }

  Future<String?> addWorkToPlaylist(int playlistId, Work work) async {
    if (!hasToken) return '请先登录';
    final no = work.workNo;
    if (no.isEmpty) return '该作品缺少编号，无法加入云端列表';
    final version = _sessionVersion;
    try {
      await _api.addWorksToPlaylist(playlistId, [no]);
      if (version != _sessionVersion) return null;
      // 乐观更新计数。
      _playlists = _playlists
          .map(
            (p) => p.id == playlistId ? p.withWorksCount(p.worksCount + 1) : p,
          )
          .toList();
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      if (version != _sessionVersion) return e.message;
      _lastError = e.message;
      notifyListeners();
      return e.message;
    }
  }

  Future<String?> removeWorkFromPlaylist(int playlistId, Work work) async {
    if (!hasToken) return '请先登录';
    final no = work.workNo;
    if (no.isEmpty) return '该作品缺少编号';
    final version = _sessionVersion;
    try {
      await _api.removeWorksFromPlaylist(playlistId, [no]);
      if (version != _sessionVersion) return null;
      _playlists = _playlists
          .map(
            (p) => p.id == playlistId
                ? p.withWorksCount((p.worksCount - 1).clamp(0, 1 << 30))
                : p,
          )
          .toList();
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      if (version != _sessionVersion) return e.message;
      _lastError = e.message;
      notifyListeners();
      return e.message;
    }
  }

  Future<PlaylistDetail> fetchPlaylistDetail(int id) =>
      _api.fetchPlaylistDetail(id);

  Future<PlaylistMembership> membershipFor(int workId) =>
      _api.fetchPlaylistMembership(workId);
}

/// 忽略返回值的后台任务（避免为此引入 `package:async`）。
void _fireAndForget(Future<void> future) {
  future.catchError((Object _) {});
}
