import 'package:asmr_one/core/api/api_client.dart';
import 'package:asmr_one/core/models/common.dart';
import 'package:asmr_one/core/models/playlist.dart';
import 'package:asmr_one/core/models/user.dart';
import 'package:asmr_one/core/storage/app_prefs.dart';
import 'package:asmr_one/state/auth_state.dart';
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
  Future<SessionInfo> fetchSession() async {
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
}
