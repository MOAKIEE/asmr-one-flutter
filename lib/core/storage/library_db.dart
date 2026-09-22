import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/work.dart';

/// 本地资料库：收藏、播放历史、本地播放列表、离线下载、收听进度。
///
/// 全部数据落在 sqflite 中，作品以 JSON 快照方式冗余存储，
/// 这样即使离线也能完整展示收藏内容。
class LibraryDb {
  LibraryDb._(this._db);

  final Database _db;

  static const int _version = 3;
  static const String _name = 'asmr_one_library.db';

  static Future<LibraryDb> open({String? path}) async {
    final dir = await getDatabasesPath();
    final db = await _openAt(path ?? p.join(dir, _name));
    return LibraryDb._(db);
  }

  static Future<Database> _openAt(String path) => openDatabase(
    path,
    version: _version,
    onCreate: _createSchema,
    onUpgrade: (db, old, next) async {
      if (old < 2) {
        await db.execute(
          'ALTER TABLE downloads ADD COLUMN track_index INTEGER NOT NULL DEFAULT 0',
        );
        await db.execute(
          "ALTER TABLE downloads ADD COLUMN folder_label TEXT NOT NULL DEFAULT ''",
        );
      }
      if (old < 3) await _createDocuments(db);
    },
  );

  static Future<void> _createSchema(Database db, int version) async {
    await _createDocuments(db);
    await db.execute('''
          CREATE TABLE favorites (
            work_id INTEGER PRIMARY KEY,
            data TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
    await db.execute('''
          CREATE TABLE history (
            work_id INTEGER PRIMARY KEY,
            data TEXT NOT NULL,
            played_at INTEGER NOT NULL,
            play_count INTEGER NOT NULL DEFAULT 1
          )
        ''');
    await db.execute('''
          CREATE TABLE local_playlists (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
    await db.execute('''
          CREATE TABLE local_playlist_items (
            playlist_id INTEGER NOT NULL,
            work_id INTEGER NOT NULL,
            data TEXT NOT NULL,
            added_at INTEGER NOT NULL,
            PRIMARY KEY (playlist_id, work_id)
          )
        ''');
    await db.execute('''
          CREATE TABLE downloads (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            work_id INTEGER NOT NULL,
            work_title TEXT,
            hash TEXT NOT NULL,
            title TEXT NOT NULL,
            file_path TEXT NOT NULL,
            size INTEGER NOT NULL DEFAULT 0,
            duration REAL NOT NULL DEFAULT 0,
            track_index INTEGER NOT NULL DEFAULT 0,
            folder_label TEXT NOT NULL DEFAULT '',
            created_at INTEGER NOT NULL,
            UNIQUE(work_id, hash)
          )
        ''');
    await db.execute('''
          CREATE TABLE progress (
            hash TEXT PRIMARY KEY,
            work_id INTEGER NOT NULL,
            position_ms INTEGER NOT NULL,
            duration_ms INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
    await db.execute(
      'CREATE INDEX idx_history_played ON history(played_at DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_download_work ON downloads(work_id, id)',
    );
  }

  // ---------------------------------------------------------------------------
  // 收藏
  // ---------------------------------------------------------------------------

  Future<List<Work>> favorites({int? limit, int offset = 0}) async {
    final rows = await _db.query(
      'favorites',
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(_decodeWork).whereType<Work>().toList();
  }

  Future<int> favoriteCount() async =>
      Sqflite.firstIntValue(
        await _db.rawQuery('SELECT COUNT(*) FROM favorites'),
      ) ??
      0;

  Future<bool> isFavorite(int workId) async {
    final rows = await _db.query(
      'favorites',
      columns: ['work_id'],
      where: 'work_id = ?',
      whereArgs: [workId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// 返回操作后的收藏状态。
  Future<bool> toggleFavorite(Work work) async {
    final exists = await isFavorite(work.id);
    if (exists) {
      await _db.delete('favorites', where: 'work_id = ?', whereArgs: [work.id]);
      return false;
    }
    await _db.insert('favorites', {
      'work_id': work.id,
      'data': jsonEncode(_workToJson(work)),
      'created_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return true;
  }

  Future<void> clearFavorites() => _db.delete('favorites');

  // ---------------------------------------------------------------------------
  // 历史
  // ---------------------------------------------------------------------------

  Future<List<Work>> history({int? limit, int offset = 0}) async {
    final rows = await _db.query(
      'history',
      orderBy: 'played_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(_decodeWork).whereType<Work>().toList();
  }

  Future<void> recordHistory(Work work) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.rawInsert(
      '''
      INSERT INTO history (work_id, data, played_at, play_count)
      VALUES (?, ?, ?, 1)
      ON CONFLICT(work_id) DO UPDATE SET
        data = excluded.data,
        played_at = excluded.played_at,
        play_count = history.play_count + 1
    ''',
      [work.id, jsonEncode(_workToJson(work)), now],
    );
  }

  Future<void> removeHistory(int workId) =>
      _db.delete('history', where: 'work_id = ?', whereArgs: [workId]);

  Future<void> clearHistory() => _db.delete('history');

  // ---------------------------------------------------------------------------
  // 本地播放列表
  // ---------------------------------------------------------------------------

  Future<List<LocalPlaylistRow>> localPlaylists() async {
    final rows = await _db.query('local_playlists', orderBy: 'created_at DESC');
    final out = <LocalPlaylistRow>[];
    for (final r in rows) {
      final id = r['id'] as int;
      final count =
          Sqflite.firstIntValue(
            await _db.rawQuery(
              'SELECT COUNT(*) FROM local_playlist_items WHERE playlist_id = ?',
              [id],
            ),
          ) ??
          0;
      out.add(
        LocalPlaylistRow(
          id: id,
          name: (r['name'] ?? '') as String,
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            (r['created_at'] ?? 0) as int,
          ),
          worksCount: count,
        ),
      );
    }
    return out;
  }

  Future<int> createLocalPlaylist(String name) => _db.insert(
    'local_playlists',
    {'name': name, 'created_at': DateTime.now().millisecondsSinceEpoch},
  );

  Future<void> renameLocalPlaylist(int id, String name) => _db.update(
    'local_playlists',
    {'name': name},
    where: 'id = ?',
    whereArgs: [id],
  );

  Future<void> deleteLocalPlaylist(int id) async {
    await _db.delete(
      'local_playlist_items',
      where: 'playlist_id = ?',
      whereArgs: [id],
    );
    await _db.delete('local_playlists', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> addToLocalPlaylist(int playlistId, Work work) =>
      _db.insert('local_playlist_items', {
        'playlist_id': playlistId,
        'work_id': work.id,
        'data': jsonEncode(_workToJson(work)),
        'added_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> removeFromLocalPlaylist(int playlistId, int workId) =>
      _db.delete(
        'local_playlist_items',
        where: 'playlist_id = ? AND work_id = ?',
        whereArgs: [playlistId, workId],
      );

  Future<List<Work>> localPlaylistWorks(int playlistId) async {
    final rows = await _db.query(
      'local_playlist_items',
      where: 'playlist_id = ?',
      whereArgs: [playlistId],
      orderBy: 'added_at DESC',
    );
    return rows.map(_decodeWork).whereType<Work>().toList();
  }

  /// 某作品已加入哪些本地列表。
  Future<List<int>> localPlaylistIdsFor(int workId) async {
    final rows = await _db.query(
      'local_playlist_items',
      columns: ['playlist_id'],
      where: 'work_id = ?',
      whereArgs: [workId],
    );
    return rows.map((e) => e['playlist_id'] as int).toList();
  }

  // ---------------------------------------------------------------------------
  // 离线下载
  // ---------------------------------------------------------------------------

  Future<void> upsertDownload(DownloadRow row) => _db.insert(
    'downloads',
    row.toMap(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  Future<List<DownloadRow>> downloads({int? workId}) async {
    final rows = await _db.query(
      'downloads',
      where: workId == null ? null : 'work_id = ?',
      whereArgs: workId == null ? null : [workId],
      orderBy: 'created_at DESC',
    );
    return rows.map(DownloadRow.fromMap).toList();
  }

  Future<void> deleteDownload(int id) =>
      _db.delete('downloads', where: 'id = ?', whereArgs: [id]);

  Future<void> deleteDownloadsOfWork(int workId) =>
      _db.delete('downloads', where: 'work_id = ?', whereArgs: [workId]);

  Future<bool> isDownloaded(String hash) async {
    final rows = await _db.query(
      'downloads',
      columns: ['id'],
      where: 'hash = ?',
      whereArgs: [hash],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<Map<String, String>> downloadedPaths(int workId) async {
    final rows = await _db.query(
      'downloads',
      columns: ['hash', 'file_path'],
      where: 'work_id = ?',
      whereArgs: [workId],
    );
    return {
      for (final r in rows) r['hash'] as String: r['file_path'] as String,
    };
  }

  // ---------------------------------------------------------------------------
  // 收听进度（用于续播）
  // ---------------------------------------------------------------------------

  Future<void> saveProgress({
    required String hash,
    required int workId,
    required int positionMs,
    required int durationMs,
  }) {
    // 结束或刚开始时不记录，避免污染续播点。
    if (durationMs <= 0) return Future.value();
    return _db.insert('progress', {
      'hash': hash,
      'work_id': workId,
      'position_ms': positionMs,
      'duration_ms': durationMs,
      'updated_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> progressFor(String hash) async {
    final rows = await _db.query(
      'progress',
      columns: ['position_ms'],
      where: 'hash = ?',
      whereArgs: [hash],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return (rows.first['position_ms'] ?? 0) as int;
  }

  Future<double> workProgressRatio(int workId) async {
    final rows = await _db.rawQuery(
      'SELECT SUM(position_ms) AS pos, SUM(duration_ms) AS dur FROM progress WHERE work_id = ?',
      [workId],
    );
    if (rows.isEmpty) return 0;
    final pos = (rows.first['pos'] as num?)?.toDouble() ?? 0;
    final dur = (rows.first['dur'] as num?)?.toDouble() ?? 0;
    if (dur <= 0) return 0;
    return (pos / dur).clamp(0.0, 1.0);
  }

  Future<void> clearProgress() => _db.delete('progress');

  Future<void> close() => _db.close();

  static Future<void> _createDocuments(Database db) => db.execute(
    'CREATE TABLE documents (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
  );

  Future<Object?> readDocument(String key) async {
    final rows = await _db.query(
      'documents',
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : jsonDecode(rows.first['value'] as String);
  }

  Future<void> writeDocument(String key, Object? value) async {
    if (value == null) {
      await _db.delete('documents', where: 'key = ?', whereArgs: [key]);
    } else {
      await _db.insert('documents', {
        'key': key,
        'value': jsonEncode(value),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  static const _backupTables = [
    'favorites',
    'history',
    'local_playlists',
    'local_playlist_items',
    'progress',
  ];

  Future<String> exportBackup() => _db.transaction((txn) async {
    final tables = <String, Object?>{};
    for (final table in _backupTables) {
      tables[table] = await txn.query(table);
    }
    tables['documents'] = await txn.query(
      'documents',
      where: "key LIKE 'bookmarks:%' OR key LIKE 'subtitle:%'",
    );
    return jsonEncode({
      'format': 'asmr-one-library',
      'version': 1,
      'tables': tables,
    });
  });

  /// Merge portable user data atomically; never import tokens, paths or queues.
  Future<void> importBackup(String source) async {
    final root = jsonDecode(source);
    if (root is! Map ||
        root['format'] != 'asmr-one-library' ||
        root['version'] != 1 ||
        root['tables'] is! Map) {
      throw const FormatException('不支持的备份格式');
    }
    final tables = root['tables'] as Map;
    for (final table in [..._backupTables, 'documents']) {
      if (tables[table] is! List ||
          (tables[table] as List).any((r) => r is! Map)) {
        throw const FormatException('备份数据不完整');
      }
    }
    await _db.transaction((txn) async {
      for (final table in ['favorites', 'history', 'progress']) {
        for (final raw in tables[table] as List) {
          final row = Map<String, Object?>.from(raw as Map);
          if (table != 'progress') {
            final data = jsonDecode(row['data'] as String);
            if (data is! Map || data['id'] != row['work_id']) {
              throw const FormatException('作品数据无效');
            }
          }
          // Existing entries win, so importing an old backup cannot rewind progress.
          await txn.insert(
            table,
            row,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }
      final ids = <int, int>{};
      for (final raw in tables['local_playlists'] as List) {
        final row = Map<String, Object?>.from(raw as Map);
        final oldId = row.remove('id') as int;
        final existing = await txn.query(
          'local_playlists',
          where: 'name = ? AND created_at = ?',
          whereArgs: [row['name'], row['created_at']],
        );
        ids[oldId] = existing.isEmpty
            ? await txn.insert('local_playlists', row)
            : existing.first['id'] as int;
      }
      for (final raw in tables['local_playlist_items'] as List) {
        final row = Map<String, Object?>.from(raw as Map);
        final id = ids[row['playlist_id']];
        if (id == null) throw const FormatException('播放列表引用无效');
        row['playlist_id'] = id;
        final data = jsonDecode(row['data'] as String);
        if ((data as Map)['id'] != row['work_id']) {
          throw const FormatException('作品数据无效');
        }
        await txn.insert(
          'local_playlist_items',
          row,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      for (final raw in tables['documents'] as List) {
        final row = Map<String, Object?>.from(raw as Map);
        final key = row['key'] as String;
        if (!key.startsWith('bookmarks:') && !key.startsWith('subtitle:')) {
          throw const FormatException('备份包含不支持的数据');
        }
        jsonDecode(row['value'] as String);
        await txn.insert(
          'documents',
          row,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    });
  }

  Future<void> clearDocuments() => _db.delete('documents');

  // ---------------------------------------------------------------------------

  Work? _decodeWork(Map<String, dynamic> row) {
    try {
      final raw = row['data'] as String?;
      if (raw == null || raw.isEmpty) return null;
      return Work.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// 只保留必要字段，减小本地快照体积。
  Map<String, dynamic> _workToJson(Work w) => {
    'id': w.id,
    'title': w.title,
    'circle_id': w.circleId,
    'name': w.circleName,
    'nsfw': w.nsfw,
    'release': w.release,
    'dl_count': w.dlCount,
    'price': w.price,
    'review_count': w.reviewCount,
    'rate_count': w.rateCount,
    'rate_average_2dp': w.rateAverage,
    'has_subtitle': w.hasSubtitle,
    'create_date': w.createDate,
    'duration': w.duration,
    'source_id': w.sourceId,
    'source_type': w.sourceType,
    'source_url': w.sourceUrl,
    'age_category_string': w.ageCategory,
    'mainCoverUrl': w.mainCoverUrl,
    'samCoverUrl': w.samCoverUrl,
    'thumbnailCoverUrl': w.thumbnailCoverUrl,
    'vas': w.vas.map((e) => e.toJson()).toList(),
    'tags': w.tags.map((e) => e.toJson()).toList(),
    'language_editions': w.languageEditions
        .map((e) => {'lang': e.lang, 'label': e.label, 'workno': e.workno})
        .toList(),
  };
}

/// 本地播放列表的行记录。
class LocalPlaylistRow {
  const LocalPlaylistRow({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.worksCount,
  });

  final int id;
  final String name;
  final DateTime createdAt;
  final int worksCount;
}

/// 离线下载记录。
class DownloadRow {
  DownloadRow({
    this.id,
    required this.workId,
    this.workTitle,
    required this.hash,
    required this.title,
    required this.filePath,
    this.size = 0,
    this.duration = 0,
    this.trackIndex = 0,
    this.folderLabel = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final int? id;
  final int workId;
  final String? workTitle;
  final String hash;
  final String title;
  final String filePath;
  final int size;
  final double duration;
  final int trackIndex;
  final String folderLabel;
  final DateTime createdAt;

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'work_id': workId,
    'work_title': workTitle,
    'hash': hash,
    'title': title,
    'file_path': filePath,
    'size': size,
    'duration': duration,
    'track_index': trackIndex,
    'folder_label': folderLabel,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory DownloadRow.fromMap(Map<String, dynamic> m) => DownloadRow(
    id: m['id'] as int?,
    workId: (m['work_id'] ?? 0) as int,
    workTitle: m['work_title'] as String?,
    hash: (m['hash'] ?? '') as String,
    title: (m['title'] ?? '') as String,
    filePath: (m['file_path'] ?? '') as String,
    size: (m['size'] ?? 0) as int,
    duration: ((m['duration'] ?? 0) as num).toDouble(),
    trackIndex: (m['track_index'] as int?) ?? 0,
    folderLabel: (m['folder_label'] as String?) ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      (m['created_at'] ?? 0) as int,
    ),
  );
}
