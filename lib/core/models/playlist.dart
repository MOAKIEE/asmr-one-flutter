import 'common.dart';
import 'work.dart';

/// 播放列表（云端收藏夹）。
class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    this.description,
    this.privacy = 'private',
    this.worksCount = 0,
    this.createdAt,
    this.updatedAt,
    this.userId,
    this.userName,
    this.isPreserved = false,
    this.likeCount = 0,
  });

  final int id;
  final String name;
  final String? description;

  /// `public` / `private` / `known`（仅登录可见）。
  final String privacy;
  final int worksCount;
  final String? createdAt;
  final String? updatedAt;
  final String? userId;
  final String? userName;

  /// 系统内置列表（如「默认收藏」「稍后听」）。
  final bool isPreserved;
  final int likeCount;

  bool get isPublic => privacy == 'public';

  factory Playlist.fromJson(Map<String, dynamic> json) {
    final user = asMap(json['user']);
    return Playlist(
      id: asInt(json['id']),
      name: asString(json['name'], '未命名列表'),
      description: asStringOrNull(json['description']),
      privacy: asString(json['privacy'], 'private'),
      worksCount: asInt(json['works_count'] ?? json['worksCount']),
      createdAt:
          asStringOrNull(json['created_at']) ??
          asStringOrNull(json['createdAt']),
      updatedAt:
          asStringOrNull(json['updated_at']) ??
          asStringOrNull(json['updatedAt']),
      userId:
          asStringOrNull(json['user_id']) ??
          (user.isEmpty ? null : asStringOrNull(user['id'])),
      userName:
          asStringOrNull(json['user_name']) ??
          (user.isEmpty ? null : asStringOrNull(user['name'])),
      isPreserved: asBool(json['is_preserved'] ?? json['isPreserved']),
      likeCount: asInt(json['like_count'] ?? json['likeCount']),
    );
  }
}

/// 播放列表详情，附带作品列表。
class PlaylistDetail {
  const PlaylistDetail({required this.playlist, required this.works});

  final Playlist playlist;
  final List<Work> works;

  factory PlaylistDetail.fromJson(Map<String, dynamic> json) {
    final meta = asMap(json['playlist']).isEmpty
        ? json
        : asMap(json['playlist']);
    final rawWorks = json['works'] ?? json['data'] ?? const [];
    return PlaylistDetail(
      playlist: Playlist.fromJson(meta),
      works: asMapList(rawWorks).map(Work.fromJson).toList(),
    );
  }
}

/// 「某作品是否已在某个播放列表里」的查询结果。
class PlaylistMembership {
  const PlaylistMembership({required this.exist, required this.playlists});

  final bool exist;
  final List<Playlist> playlists;

  factory PlaylistMembership.fromJson(Map<String, dynamic> json) {
    final raw = json['playlists'] ?? json['data'] ?? const [];
    return PlaylistMembership(
      exist: asBool(json['exist'] ?? json['exists']),
      playlists: asMapList(raw).map(Playlist.fromJson).toList(),
    );
  }

  static const none = PlaylistMembership(exist: false, playlists: []);
}

/// 本地（离线）播放列表，存于 sqflite。
class LocalPlaylist {
  const LocalPlaylist({
    required this.id,
    required this.name,
    required this.createdAt,
    this.works = const [],
  });

  final int id;
  final String name;
  final DateTime createdAt;
  final List<Work> works;
}
