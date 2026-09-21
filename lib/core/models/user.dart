import 'common.dart';

/// 当前登录用户。/api/auth/me 匿名访问时返回 `{loggedIn: false}`。
class AppUser {
  const AppUser({
    required this.loggedIn,
    this.id,
    this.name,
    this.email,
    this.group,
    this.avatarUrl,
    this.playlistDefault,
  });

  final bool loggedIn;
  final String? id;
  final String? name;
  final String? email;
  final String? group;
  final String? avatarUrl;

  /// 默认收藏目标列表名称。
  final String? playlistDefault;

  static const anonymous = AppUser(loggedIn: false);

  String get displayName => name ?? '未登录';

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
    loggedIn: asBool(json['loggedIn'] ?? json['logged_in'], true),
    id: asStringOrNull(json['id']),
    name: asStringOrNull(json['name']),
    email: asStringOrNull(json['email']),
    group: asStringOrNull(json['group']),
    avatarUrl:
        asStringOrNull(json['avatarUrl']) ?? asStringOrNull(json['avatar_url']),
    playlistDefault:
        asStringOrNull(json['playlistDefault']) ??
        asStringOrNull(json['playlist_default']),
  );
}

/// `/api/auth/me` 的完整响应：用户信息 + 服务端能力开关。
class SessionInfo {
  const SessionInfo({
    required this.user,
    required this.authEnabled,
    required this.regEnabled,
  });

  final AppUser user;

  /// 服务端是否开启登录。
  final bool authEnabled;

  /// 服务端是否开启注册。
  final bool regEnabled;

  factory SessionInfo.fromJson(Map<String, dynamic> json) => SessionInfo(
    user: AppUser.fromJson(asMap(json['user'])),
    authEnabled: asBool(json['auth'], true),
    regEnabled: asBool(json['reg'], true),
  );

  static const anonymous = SessionInfo(
    user: AppUser.anonymous,
    authEnabled: true,
    regEnabled: true,
  );
}
