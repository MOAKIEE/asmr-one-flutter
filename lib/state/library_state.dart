import 'package:flutter/foundation.dart';

import '../core/models/work.dart';
import '../core/storage/library_db.dart';

/// 本地资料库状态：收藏、历史、本地播放列表、离线下载。
///
/// 所有写操作串行化（[_lock]），避免 sqflite 并发写入导致的竞态。
class LibraryState extends ChangeNotifier {
  LibraryState(this._db);

  final LibraryDb _db;

  Future<Object?> readDocument(String key) => _db.readDocument(key);
  Future<void> writeDocument(String key, Object? value) =>
      _serial(() => _db.writeDocument(key, value));
  Future<String> exportBackup() => _serial(_db.exportBackup);
  Future<void> importBackup(String source) async {
    await _serial(() => _db.importBackup(source));
    await refresh();
  }

  Future<void> _lock = Future.value();

  List<Work> _favorites = const [];
  List<Work> _history = const [];
  List<LocalPlaylistRow> _localPlaylists = const [];
  List<DownloadRow> _downloads = const [];
  Set<int> _favoriteIds = {};

  List<Work> get favorites => _favorites;
  List<Work> get history => _history;
  List<LocalPlaylistRow> get localPlaylists => _localPlaylists;
  List<DownloadRow> get downloads => _downloads;

  bool isFavorite(int workId) => _favoriteIds.contains(workId);
  int get favoriteCount => _favoriteIds.length;

  int get downloadBytes =>
      _downloads.fold(0, (sum, d) => sum + (d.size <= 0 ? 0 : d.size));

  Future<T> _serial<T>(Future<T> Function() action) {
    final completer = _lock.then((_) => action());
    _lock = completer.then((_) {}).catchError((Object _) {});
    return completer;
  }

  Future<void> refresh() => _serial(() async {
    _favorites = await _db.favorites();
    _favoriteIds = _favorites.map((e) => e.id).toSet();
    _history = await _db.history();
    _localPlaylists = await _db.localPlaylists();
    _downloads = await _db.downloads();
    notifyListeners();
  });

  // ---------------------------------------------------------------------------
  // 收藏
  // ---------------------------------------------------------------------------

  Future<bool> toggleFavorite(Work work) => _serial(() async {
    final nowFav = await _db.toggleFavorite(work);
    if (nowFav) {
      _favoriteIds = {..._favoriteIds, work.id};
      _favorites = [work, ..._favorites.where((e) => e.id != work.id)];
    } else {
      _favoriteIds = {..._favoriteIds}..remove(work.id);
      _favorites = _favorites.where((e) => e.id != work.id).toList();
    }
    notifyListeners();
    return nowFav;
  });

  // ---------------------------------------------------------------------------
  // 历史
  // ---------------------------------------------------------------------------

  Future<void> recordHistory(Work work) => _serial(() async {
    await _db.recordHistory(work);
    _history = [work, ..._history.where((e) => e.id != work.id)];
    notifyListeners();
  });

  Future<void> removeHistory(int workId) => _serial(() async {
    await _db.removeHistory(workId);
    _history = _history.where((e) => e.id != workId).toList();
    notifyListeners();
  });

  Future<void> clearHistory() => _serial(() async {
    await _db.clearHistory();
    _history = const [];
    notifyListeners();
  });

  // ---------------------------------------------------------------------------
  // 本地播放列表
  // ---------------------------------------------------------------------------

  Future<int> createLocalPlaylist(String name) => _serial(() async {
    final id = await _db.createLocalPlaylist(name);
    _localPlaylists = await _db.localPlaylists();
    notifyListeners();
    return id;
  });

  Future<void> renameLocalPlaylist(int id, String name) => _serial(() async {
    await _db.renameLocalPlaylist(id, name);
    _localPlaylists = await _db.localPlaylists();
    notifyListeners();
  });

  Future<void> deleteLocalPlaylist(int id) => _serial(() async {
    await _db.deleteLocalPlaylist(id);
    _localPlaylists = await _db.localPlaylists();
    notifyListeners();
  });

  Future<void> addToLocalPlaylist(int playlistId, Work work) =>
      _serial(() async {
        await _db.addToLocalPlaylist(playlistId, work);
        _localPlaylists = await _db.localPlaylists();
        notifyListeners();
      });

  Future<void> removeFromLocalPlaylist(int playlistId, int workId) =>
      _serial(() async {
        await _db.removeFromLocalPlaylist(playlistId, workId);
        _localPlaylists = await _db.localPlaylists();
        notifyListeners();
      });

  Future<List<Work>> localPlaylistWorks(int playlistId) =>
      _db.localPlaylistWorks(playlistId);

  Future<List<int>> localPlaylistIdsFor(int workId) =>
      _db.localPlaylistIdsFor(workId);

  // ---------------------------------------------------------------------------
  // 下载
  // ---------------------------------------------------------------------------

  Future<void> refreshDownloads() => _serial(() async {
    _downloads = await _db.downloads();
    notifyListeners();
  });

  Future<void> saveDownload(DownloadRow row) => _serial(() async {
    await _db.upsertDownload(row);
    _downloads = await _db.downloads();
    notifyListeners();
  });

  Future<void> deleteDownload(int id) => _serial(() async {
    await _db.deleteDownload(id);
    _downloads = await _db.downloads();
    notifyListeners();
  });

  Future<void> deleteDownloadsOfWork(int workId) => _serial(() async {
    await _db.deleteDownloadsOfWork(workId);
    _downloads = await _db.downloads();
    notifyListeners();
  });

  Future<Map<String, String>> downloadedPaths(int workId) =>
      _db.downloadedPaths(workId);

  /// 某个作品已下载的音频记录。
  Future<List<DownloadRow>> downloadsFor(int workId) =>
      _db.downloads(workId: workId);

  /// 已下载作品 id 集合（用于「已下载」标识）。
  Set<int> get downloadedWorkIds => _downloads.map((d) => d.workId).toSet();

  bool get hasDownloads => _downloads.isNotEmpty;

  Future<bool> isDownloaded(String hash) => _db.isDownloaded(hash);

  // ---------------------------------------------------------------------------
  // 进度
  // ---------------------------------------------------------------------------

  Future<void> saveProgress({
    required String hash,
    required int workId,
    required int positionMs,
    required int durationMs,
  }) => _serial(
    () => _db.saveProgress(
      hash: hash,
      workId: workId,
      positionMs: positionMs,
      durationMs: durationMs,
    ),
  );

  Future<int> progressFor(String hash) => _db.progressFor(hash);

  Future<double> workProgressRatio(int workId) => _db.workProgressRatio(workId);

  // ---------------------------------------------------------------------------

  Future<void> clearAllLocalData() => _serial(() async {
    await _db.clearFavorites();
    await _db.clearHistory();
    for (final p in await _db.localPlaylists()) {
      await _db.deleteLocalPlaylist(p.id);
    }
    await _db.clearProgress();
    await _db.clearDocuments();
    _favorites = const [];
    _favoriteIds = {};
    _history = const [];
    _localPlaylists = const [];
    notifyListeners();
  });
}
