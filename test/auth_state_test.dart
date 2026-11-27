import 'dart:async';

import 'package:mimori/core/api/api_client.dart';
import 'package:mimori/core/models/common.dart';
import 'package:mimori/core/models/playlist.dart';
import 'package:mimori/core/models/user.dart';
import 'package:mimori/core/storage/app_prefs.dart';
import 'package:mimori/state/auth_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessionApi extends ApiClient {
  SessionInfo session = const SessionInfo(
    user: AppUser(loggedIn: true, name: 'test'),
    authEnabled: true,
    regEnabled: true,
  );
  ApiException? error;
  int playlistCalls = 0;
  int tagCalls = 0;

  @override
  Future<String> login(String name, String password) async => 'candidate';

  @override
  Future<SessionInfo> fetchSession({String? sessionToken}) async {
    if (error != null) throw error!;
    return session;
  }

  @override
  Future<List<Playlist>> fetchMyPlaylists({
    int page = 1,
    int pageSize = 100,
  }) async {
    playlistCalls++;
    return [const Playlist(id: 7, name: 'Saved list')];
  }

  @override
  Future<List<Tag>> fetchTags({int page = 1, int pageSize = 500}) async {
    tagCalls++;
    return [
      Tag.fromJson({'id': 42, 'name': 'Server tag'}),
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppPrefs prefs;
  late SessionApi api;
  late AuthState auth;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'auth.token': 'saved-token'});
    prefs = await AppPrefs.load();
    api = SessionApi();
    auth = AuthState(prefs, api: api);
  });
  tearDown(() => auth.dispose());

  test(
    'restored login loads playlists and full tags without another login',
    () async {
      await auth.bootstrap();
      await Future<void>.delayed(Duration.zero);
      expect(auth.loggedIn, isTrue);
      expect(auth.playlists.single.id, 7);
      expect(auth.tags.single.id, 42);
      expect(auth.usingBundledTags, isFalse);
      expect(api.playlistCalls, 1);
      expect(api.tagCalls, 1);
    },
  );
  test('anonymous session does not fetch cloud data', () async {
    api.session = SessionInfo.anonymous;
    await auth.bootstrap();
    expect(api.playlistCalls, 0);
    expect(api.tagCalls, 0);
  });
  test('expired token is cleared before any cloud request', () async {
    api.error = ApiException('expired', statusCode: 401);
    await auth.bootstrap();
    expect(auth.hasToken, isFalse);
    expect(prefs.token, isNull);
    expect(api.playlistCalls, 0);
    expect(api.tagCalls, 0);
  });
  test('offline startup retains the saved token', () async {
    api.error = ApiException('offline');
    await auth.bootstrap();
    expect(prefs.token, 'saved-token');
    expect(api.playlistCalls, 0);
    expect(api.tagCalls, 0);
  });

  test(
    'anonymous bootstrap with authEnabled clears persisted cache scope and notifies player, while offline startup preserves it',
    () async {
      // 1. Offline failure keeps persisted accountScope and does not trigger onTokenChanged.
      SharedPreferences.setMockInitialValues({
        'auth.token': 'saved-token',
        'auth.accountScope': 'uid:A',
      });
      final offlinePrefs = await AppPrefs.load();
      var offlineCallbacks = 0;
      final offlineApi = SessionApi()..error = ApiException('offline');
      final offlineAuth = AuthState(
        offlinePrefs,
        api: offlineApi,
        onTokenChanged: () async => offlineCallbacks++,
      );
      addTearDown(offlineAuth.dispose);

      await offlineAuth.bootstrap();
      expect(offlineAuth.cacheAccountScope, 'uid:A');
      expect(offlinePrefs.accountScope, 'uid:A');
      expect(offlineCallbacks, 0);

      // 2. Server explicitly returns loggedIn=false with authEnabled=true -> clears uid:A and notifies player.
      SharedPreferences.setMockInitialValues({
        'auth.token': 'saved-token',
        'auth.accountScope': 'uid:A',
      });
      final anonPrefs = await AppPrefs.load();
      var anonCallbacks = 0;
      final anonApi = SessionApi()
        ..session = const SessionInfo(
          user: AppUser.anonymous,
          authEnabled: true,
          regEnabled: true,
        );
      final anonAuth = AuthState(
        anonPrefs,
        api: anonApi,
        onTokenChanged: () async => anonCallbacks++,
      );
      addTearDown(anonAuth.dispose);

      await anonAuth.bootstrap();
      expect(anonAuth.loggedIn, isFalse);
      expect(anonAuth.cacheAccountScope, isNull);
      expect(anonPrefs.accountScope, isNull);
      expect(anonCallbacks, 1);
    },
  );

  test('rejected session leaves a signed-out user without credentials', () async {
    await auth.logout();
    api.error = ApiException('expired', statusCode: 401);
    expect(await auth.login('new-user', 'password'), isFalse);
    expect(auth.loggedIn, isFalse);
    expect(auth.hasToken, isFalse);
    expect(prefs.token, isNull);
    expect(auth.lastError, 'expired');
    expect(auth.busy, isFalse);
    expect(api.playlistCalls, 0);
  });

  test('failed account switch preserves the verified account and lists', () async {
    await auth.bootstrap();
    await Future<void>.delayed(Duration.zero);
    api.error = ApiException('offline');
    expect(await auth.login('new-user', 'password'), isFalse);
    expect(auth.loggedIn, isTrue);
    expect(auth.user.name, 'test');
    expect(prefs.token, 'saved-token');
    expect(auth.playlists.single.id, 7);
    expect(api.playlistCalls, 1);
    expect(auth.lastError, 'offline');
  });

  test('a session without a user cannot confirm a new login', () async {
    await auth.logout();
    api.session = SessionInfo.fromJson({});
    expect(await auth.login('new-user', 'password'), isFalse);
    expect(auth.loggedIn, isFalse);
    expect(prefs.token, isNull);
  });

  test(
    'late responses from account A never overwrite logged-out or account B state',
    () async {
      final switcherApi = _AccountSwitchApi();
      final switcher = AuthState(prefs, api: switcherApi);
      addTearDown(switcher.dispose);

      // 1) A 登录并开始请求私有列表，同时挂起
      await switcher.login('userA', 'secretA');
      await Future<void>.delayed(Duration.zero);
      expect(switcherApi.pendingPlaylists, hasLength(1));
      final aPlaylistsFuture = switcherApi.pendingPlaylists.removeAt(0);

      // 2) 退出后登录 B，并让 B 先返回自己的列表
      await switcher.logout();
      expect(switcher.playlists, isEmpty);
      expect(switcher.playlistsLoaded, isFalse);

      await switcher.login('userB', 'secretB');
      await Future<void>.delayed(Duration.zero);
      expect(switcherApi.pendingPlaylists, hasLength(1));
      final bPlaylistsFuture = switcherApi.pendingPlaylists.removeAt(0);

      bPlaylistsFuture.complete([
        const Playlist(id: 200, name: 'B private'),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(switcher.playlists.map((e) => e.id), [200]);
      expect(switcher.playlistsLoaded, isTrue);

      // 3) A 的列表响应最后才到达，不应覆盖 B 的列表
      aPlaylistsFuture.complete([
        const Playlist(id: 100, name: 'A secret'),
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(switcher.playlists.map((e) => e.id), [200]);
      expect(switcher.lastError, isNull);

      // 4) A 的响应在 B 请求仍在途时先到达，不应把 B 的 playlistsLoaded 标为 true
      await switcher.login('userA', 'secretA');
      await Future<void>.delayed(Duration.zero);
      final a2Playlists = switcherApi.pendingPlaylists.removeAt(0);
      await switcher.login('userB', 'secretB');
      await Future<void>.delayed(Duration.zero);
      final b2Playlists = switcherApi.pendingPlaylists.removeAt(0);

      a2Playlists.complete([const Playlist(id: 101, name: 'A leaked')]);
      await Future<void>.delayed(Duration.zero);
      expect(switcher.playlists, isEmpty);
      expect(switcher.playlistsLoaded, isFalse);

      b2Playlists.complete([const Playlist(id: 201, name: 'B fresh')]);
      await Future<void>.delayed(Duration.zero);
      expect(switcher.playlists.map((e) => e.id), [201]);
      expect(switcher.playlistsLoaded, isTrue);

      // 5) 退出后旧请求异常迟到也不得覆盖错误标记或加载状态
      await switcher.login('userA', 'secretA');
      await Future<void>.delayed(Duration.zero);
      expect(switcherApi.pendingPlaylists, hasLength(1));
      final a3Playlists = switcherApi.pendingPlaylists.removeAt(0);

      await switcher.logout();
      a3Playlists.completeError(ApiException('A stale error', statusCode: 500));
      await Future<void>.delayed(Duration.zero);
      expect(switcher.playlists, isEmpty);
      expect(switcher.playlistsLoaded, isFalse);
      expect(switcher.lastError, isNull);
    },
  );

  test(
    'login stays busy until onTokenChanged finishes so callers cannot double-submit',
    () async {
      final refresh = Completer<void>();
      final state = AuthState(
        prefs,
        api: api,
        onTokenChanged: () => refresh.future,
      );
      addTearDown(state.dispose);

      final pending = state.login('alice', 'secret');
      await Future<void>.delayed(Duration.zero);
      expect(state.loggedIn, isTrue);
      expect(state.busy, isTrue);

      refresh.complete();
      expect(await pending, isTrue);
      expect(state.busy, isFalse);
    },
  );
}

class _AccountSwitchApi extends ApiClient {
  String _currentUser = 'userA';
  final List<Completer<List<Playlist>>> pendingPlaylists = [];

  @override
  Future<String> login(String name, String password) async {
    _currentUser = name;
    return 'token-$name';
  }

  @override
  Future<SessionInfo> fetchSession({String? sessionToken}) async => SessionInfo(
    user: AppUser(loggedIn: true, name: _currentUser),
    authEnabled: true,
    regEnabled: true,
  );

  @override
  Future<List<Playlist>> fetchMyPlaylists({
    int page = 1,
    int pageSize = 100,
  }) {
    final completer = Completer<List<Playlist>>();
    pendingPlaylists.add(completer);
    return completer.future;
  }

  @override
  Future<List<Tag>> fetchTags({int page = 1, int pageSize = 500}) async => [];
}
