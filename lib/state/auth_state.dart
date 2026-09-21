import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../core/data/tag_catalog.dart';
import '../core/models/common.dart';
import '../core/models/playlist.dart';
import '../core/models/user.dart';
import '../core/models/work.dart';
import '../core/storage/app_prefs.dart';

/// 登录状态 + 依赖登录态的云端数据（播放列表、标签目录）。
class AuthState extends ChangeNotifier {
  AuthState(this._prefs) {
    _api.attachPrefs(_prefs);
    _token = _prefs.token;
  }

  final AppPrefs _prefs;
  final ApiClient _api = ApiClient.instance;

  String? _token;
  AppUser _user = AppUser.anonymous;
  bool _authEnabled = true;
  bool _regEnabled = true;
  bool _busy = false;
  String? _lastError;

  List<Playlist> _playlists = const [];
  bool _playlistsLoaded = false;
  List<Tag>? _serverTags;

  // --- 只读访问 ---
  bool get loggedIn => (_token ?? '').isNotEmpty && _user.loggedIn;
  bool get hasToken => (_token ?? '').isNotEmpty;
  AppUser get user => _user;
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
    try {
      final session = await _api.fetchSession();
      _authEnabled = session.authEnabled;
      _regEnabled = session.regEnabled;
      if (session.user.loggedIn) {
        _user = session.user;
      } else if (!session.authEnabled && hasToken) {
        // 服务端关闭了登录，本地令牌已无意义。
        _user = AppUser.anonymous;
      } else {
        _user = AppUser.anonymous;
      }
    } on ApiException catch (e) {
      if (e.isAuthError) {
        _token = null;
        _prefs.token = null;
        _user = AppUser.anonymous;
      }
      _lastError = e.message;
    } catch (_) {
      // 静默失败：保持本地状态，离线可用。
    }
    notifyListeners();
  }

  Future<bool> login(String name, String password) async {
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      final t = await _api.login(name.trim(), password);
      _token = t;
      _prefs.token = t;
      final session = await _api.fetchSession();
      _user = session.user.loggedIn
          ? session.user
          : AppUser(loggedIn: true, name: name.trim());
      _authEnabled = session.authEnabled;
      _regEnabled = session.regEnabled;
      _busy = false;
      notifyListeners();
      // 登录后异步补齐云端数据，不阻塞界面。
      _fireAndForget(_loadCloudData());
      return true;
    } on ApiException catch (e) {
      _lastError = e.message;
      _busy = false;
      notifyListeners();
      return false;
    } catch (e) {
      _lastError = '$e';
      _busy = false;
      notifyListeners();
      return false;
    }
  }

  Future<String?> register(String name, String password) async {
    _busy = true;
    _lastError = null;
    notifyListeners();
    try {
      await _api.register(name.trim(), password);
      _busy = false;
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      _lastError = e.message;
      _busy = false;
      notifyListeners();
      return e.message;
    } catch (e) {
      _lastError = '$e';
      _busy = false;
      notifyListeners();
      return '$e';
    }
  }

  Future<void> logout() async {
    _token = null;
    _prefs.token = null;
    _user = AppUser.anonymous;
    _playlists = const [];
    _playlistsLoaded = false;
    _serverTags = null;
    _lastError = null;
    notifyListeners();
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
    if (!hasToken) return;
    try {
      final list = await _api.fetchTags();
      if (list.isNotEmpty) {
        _serverTags = list;
        notifyListeners();
      }
    } catch (_) {
      // 失败则继续使用内置目录。
    }
  }

  Future<void> loadPlaylists({bool force = false}) async {
    if (!hasToken) {
      _playlists = const [];
      _playlistsLoaded = true;
      notifyListeners();
      return;
    }
    if (_playlistsLoaded && !force) return;
    try {
      _playlists = await _api.fetchMyPlaylists();
      _playlistsLoaded = true;
      _lastError = null;
    } on ApiException catch (e) {
      // 401 情况已在 ApiClient 里翻译成中文提示。
      if (e.statusCode == 404 || e.statusCode == 400) {
        _playlists = const [];
      }
      _lastError = e.statusCode == 404 ? null : e.message;
      _playlistsLoaded = true;
    } catch (_) {
      _playlistsLoaded = true;
    }
    notifyListeners();
  }

  Future<Playlist?> createPlaylist({
    required String name,
    String? description,
    String privacy = 'private',
  }) async {
    try {
      final p = await _api.createPlaylist(
        name: name,
        description: description,
        privacy: privacy,
      );
      _playlists = [p, ..._playlists];
      notifyListeners();
      return p;
    } on ApiException catch (e) {
      _lastError = e.message;
      notifyListeners();
      return null;
    }
  }

  Future<String?> addWorkToPlaylist(int playlistId, Work work) async {
    if (!hasToken) return '请先登录';
    final no = work.workNo;
    if (no.isEmpty) return '该作品缺少编号，无法加入云端列表';
    try {
      await _api.addWorksToPlaylist(playlistId, [no]);
      // 乐观更新计数。
      _playlists = _playlists
          .map(
            (p) => p.id == playlistId
                ? Playlist(
                    id: p.id,
                    name: p.name,
                    description: p.description,
                    privacy: p.privacy,
                    worksCount: p.worksCount + 1,
                    createdAt: p.createdAt,
                    updatedAt: p.updatedAt,
                    userId: p.userId,
                    userName: p.userName,
                    isPreserved: p.isPreserved,
                    likeCount: p.likeCount,
                  )
                : p,
          )
          .toList();
      notifyListeners();
      return null;
    } on ApiException catch (e) {
      _lastError = e.message;
      notifyListeners();
      return e.message;
    }
  }

  Future<String?> removeWorkFromPlaylist(int playlistId, Work work) async {
    if (!hasToken) return '请先登录';
    final no = work.workNo;
    if (no.isEmpty) return '该作品缺少编号';
    try {
      await _api.removeWorksFromPlaylist(playlistId, [no]);
      _playlists = _playlists
          .map(
            (p) => p.id == playlistId
                ? Playlist(
                    id: p.id,
                    name: p.name,
                    description: p.description,
                    privacy: p.privacy,
                    worksCount: (p.worksCount - 1).clamp(0, 1 << 30),
                    createdAt: p.createdAt,
                    updatedAt: p.updatedAt,
                    userId: p.userId,
                    userName: p.userName,
                    isPreserved: p.isPreserved,
                    likeCount: p.likeCount,
                  )
                : p,
          )
          .toList();
      notifyListeners();
      return null;
    } on ApiException catch (e) {
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
