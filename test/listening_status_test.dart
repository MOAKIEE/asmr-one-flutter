import 'dart:async';

import 'package:asmr_one/core/api/api_client.dart';
import 'package:asmr_one/core/models/review.dart';
import 'package:asmr_one/core/models/work.dart';
import 'package:asmr_one/core/storage/app_prefs.dart';
import 'package:asmr_one/core/storage/library_db.dart';
import 'package:asmr_one/l10n/app_localizations.dart';
import 'package:asmr_one/screens/login_screen.dart';
import 'package:asmr_one/screens/work_detail_screen.dart';
import 'package:asmr_one/state/auth_state.dart';
import 'package:asmr_one/state/download_state.dart';
import 'package:asmr_one/state/library_state.dart';
import 'package:asmr_one/state/player_state.dart';
import 'package:asmr_one/state/settings_state.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client_test.dart' show TestAdapter, jsonResponse;
import 'download_state_test.dart' show DownloadLibrary;
import 'player_state_test.dart' show TestAudio;

class _StatusLibrary extends DownloadLibrary {
  final Set<int> _favorites = {42};
  final Map<String, int> _progress = {'42/0': 95000};

  @override
  bool isFavorite(int workId) => _favorites.contains(workId);

  @override
  Set<int> get downloadedWorkIds => const {};

  @override
  List<LocalPlaylistRow> get localPlaylists => const [];

  @override
  Future<int> progressFor(String hash) async => _progress[hash] ?? 0;

  @override
  Future<void> recordHistory(Work work) async {}

  @override
  Future<void> saveProgress({
    required String hash,
    required int workId,
    required int positionMs,
    required int durationMs,
  }) async {
    _progress[hash] = positionMs;
  }
}

Widget _wrapDetail({
  required SettingsState settings,
  required AuthState auth,
  required LibraryState library,
  required DownloadState downloads,
  required PlayerState player,
  required Widget home,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<SettingsState>.value(value: settings),
      ChangeNotifierProvider<AuthState>.value(value: auth),
      ChangeNotifierProvider<LibraryState>.value(value: library),
      ChangeNotifierProvider<DownloadState>.value(value: downloads),
      ChangeNotifierProvider<PlayerState>.value(value: player),
    ],
    child: MaterialApp(
      locale: settings.locale,
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    ),
  );
}

void main() {
  test('ListeningStatus maps all 5 API values and translates in 3 locales', () {
    final zh = L10n.forLocale(const Locale('zh', 'CN'));
    final ja = L10n.forLocale(const Locale('ja', 'JP'));
    final en = L10n.forLocale(const Locale('en', 'US'));

    expect(ListeningStatus.fromApi('marked'), ListeningStatus.marked);
    expect(ListeningStatus.fromApi('listening'), ListeningStatus.listening);
    expect(ListeningStatus.fromApi('listened'), ListeningStatus.listened);
    expect(ListeningStatus.fromApi('replay'), ListeningStatus.replay);
    expect(ListeningStatus.fromApi('postponed'), ListeningStatus.postponed);
    expect(ListeningStatus.fromApi('unknown'), isNull);
    expect(ListeningStatus.fromApi(null), isNull);

    for (final status in ListeningStatus.values) {
      expect(zh(status.labelKey), isNot(status.labelKey));
      expect(ja(status.labelKey), isNot(status.labelKey));
      expect(en(status.labelKey), isNot(status.labelKey));
      expect(zh(status.hintKey), isNot(status.hintKey));
      expect(ja(status.hintKey), isNot(status.hintKey));
      expect(en(status.hintKey), isNot(status.hintKey));
    }
  });

  test(
    'updateWorkProgress sends PUT /api/review with only work_id and progress while preserving rating and review text',
    () async {
      SharedPreferences.setMockInitialValues({'auth.token': 'tok-a'});
      final prefs = await AppPrefs.load();
      var serverProgress = 'listening';
      const serverRating = 4.5;
      const serverReviewText = 'Very relaxing rain sound';

      final adapter = TestAdapter((request) {
        if (request.method == 'PUT' && request.uri.path == '/api/review') {
          final body = request.data as Map;
          expect(body.keys.toSet(), {'work_id', 'progress'});
          expect(body['work_id'], 42);
          expect(body['progress'], 'postponed');
          expect(request.headers['Authorization'], 'Bearer tok-a');
          serverProgress = body['progress'] as String;
          return jsonResponse({'message': 'ok'});
        }
        if (request.method == 'GET' && request.uri.path == '/api/work/42') {
          expect(request.headers['Authorization'], 'Bearer tok-a');
          return jsonResponse({
            'id': 42,
            'title': 'Rainy Night',
            'userRating': serverRating,
            'review_text': serverReviewText,
            'progress': serverProgress,
          });
        }
        return jsonResponse({});
      });
      final api = ApiClient(adapter: adapter)..attachPrefs(prefs);

      final before = await api.fetchWork(42);
      expect(before.listeningStatus, ListeningStatus.listening);
      expect(before.userRating, serverRating);
      expect(before.reviewText, serverReviewText);

      await api.updateWorkProgress(
        workId: 42,
        status: ListeningStatus.postponed,
      );

      final after = await api.fetchWork(42);
      expect(after.listeningStatus, ListeningStatus.postponed);
      expect(after.userRating, serverRating);
      expect(after.reviewText, serverReviewText);
    },
  );

  test(
    'fetchMyListeningStatusFromReviews scans beyond page 1 before concluding unmarked',
    () async {
      SharedPreferences.setMockInitialValues({'auth.token': 'tok-a'});
      final prefs = await AppPrefs.load();
      final requestedPages = <int>[];
      final adapter = TestAdapter((request) {
        final page = request.queryParameters['page'] as int;
        requestedPages.add(page);
        if (page == 1) {
          return jsonResponse({
            'reviews': [
              {
                'id': 1,
                'work_id': 42,
                'rating': 5,
                'progress': 'listened',
                'user_name': 'other_user',
              },
            ],
            'page': 1,
            'pageSize': 1,
            'totalCount': 2,
          });
        }
        return jsonResponse({
          'reviews': [
            {
              'id': 2,
              'work_id': 42,
              'rating': 4,
              'progress': 'replay',
              'user_name': 'alice',
            },
          ],
          'page': 2,
          'pageSize': 1,
          'totalCount': 2,
        });
      });
      final api = ApiClient(adapter: adapter)..attachPrefs(prefs);

      final status = await api.fetchMyListeningStatusFromReviews(
        42,
        userName: 'alice',
        pageSize: 1,
      );
      expect(requestedPages, [1, 2]);
      expect(status, ListeningStatus.replay);
    },
  );

  testWidgets(
    'WorkDetailScreen updates listening status, reads it back on reopen, and preserves rating, review, favorite, and progress',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'auth.token': 'tok-alice',
        'ui.locale': 'zh-CN',
        'ui.useCoverAccent': false,
      });
      final prefs = await AppPrefs.load();
      final settings = SettingsState(prefs);
      final library = _StatusLibrary();
      final downloads = DownloadState(library);
      final player = PlayerState(
        settings: settings,
        library: library,
        audioPlayer: TestAudio(),
      );

      var serverProgress = 'listening';
      final api = ApiClient(
        adapter: TestAdapter((request) {
          if (request.uri.path == '/api/auth/me') {
            return jsonResponse({
              'user': {'loggedIn': true, 'id': 'u1', 'name': 'alice'},
              'auth': true,
              'reg': true,
            });
          }
          if (request.method == 'GET' && request.uri.path == '/api/work/42') {
            return jsonResponse({
              'id': 42,
              'title': 'Marked Work',
              'userRating': 5,
              'review_text': 'Kept review text',
              'progress': serverProgress,
            });
          }
          if (request.method == 'PUT' && request.uri.path == '/api/review') {
            final body = request.data as Map;
            expect(body, {'work_id': 42, 'progress': 'postponed'});
            serverProgress = body['progress'] as String;
            return jsonResponse({'ok': true});
          }
          if (request.uri.path == '/api/tracks/42') {
            return jsonResponse([]);
          }
          if (request.uri.path == '/api/review') {
            return jsonResponse({
              'reviews': [
                {
                  'id': 1,
                  'work_id': 42,
                  'rating': 5,
                  'review_text': 'Kept review text',
                  'progress': serverProgress,
                  'user_name': 'alice',
                },
              ],
              'page': 1,
              'pageSize': 10,
              'totalCount': 1,
            });
          }
          return jsonResponse({'works': [], 'pagination': {'totalCount': 0}});
        }),
      )..attachPrefs(prefs);
      final auth = AuthState(prefs, api: api);
      await tester.runAsync(() => auth.bootstrap());

      await tester.pumpWidget(
        _wrapDetail(
          settings: settings,
          auth: auth,
          library: library,
          downloads: downloads,
          player: player,
          home: WorkDetailScreen(
            work: Work.fromJson({'id': 42, 'title': 'Marked Work'}),
            api: api,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially read back as "在听".
      expect(find.text('在听'), findsWidgets);

      // Change from "在听" to "搁置".
      await tester.tap(find.text('收听状态'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('搁置'));
      await tester.pumpAndSettle();
      expect(find.text('搁置'), findsWidgets);

      // Exit and reopen WorkDetailScreen: reads back "搁置" while favorite & playback progress remain intact.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        _wrapDetail(
          settings: settings,
          auth: auth,
          library: library,
          downloads: downloads,
          player: player,
          home: WorkDetailScreen(
            work: Work.fromJson({'id': 42, 'title': 'Marked Work'}),
            api: api,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('搁置'), findsWidgets);
      await tester.scrollUntilVisible(
        find.text('Kept review text'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Kept review text'), findsOneWidget);
      expect(library.isFavorite(42), isTrue);
      expect(await library.progressFor('42/0'), 95000);

      await tester.pumpWidget(const SizedBox());
      player.dispose();
      downloads.dispose();
      library.dispose();
      auth.dispose();
      settings.dispose();
    },
  );

  testWidgets(
    'WorkDetailScreen handles guest login prompt, server rejection, timeout readback, work switch, and account switch/logout',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({
        'ui.locale': 'zh-CN',
        'ui.useCoverAccent': false,
      });
      final prefs = await AppPrefs.load();
      final settings = SettingsState(prefs);
      final library = _StatusLibrary();
      final downloads = DownloadState(library);
      final player = PlayerState(
        settings: settings,
        library: library,
        audioPlayer: TestAudio(),
      );

      var rejectWrite = false;
      var timeoutWrite = false;
      final accountProgress = <String, Map<int, String?>>{
        'tok-a': {42: 'listening', 99: 'marked'},
        'tok-b': {42: 'replay', 99: null},
      };
      Completer<void>? holdWrite;

      final adapter = TestAdapter((request) {
        final authHeader = request.headers['Authorization'] as String?;
        final tok = authHeader?.replaceFirst('Bearer ', '') ?? '';
        if (request.method == 'POST' && request.uri.path == '/api/auth/me') {
          final name = (request.data as Map)['name'] as String;
          return jsonResponse({'token': name == 'alice' ? 'tok-a' : 'tok-b'});
        }
        if (request.method == 'GET' && request.uri.path == '/api/auth/me') {
          if (tok == 'tok-a') {
            return jsonResponse({
              'user': {'loggedIn': true, 'id': 'u1', 'name': 'alice'},
              'auth': true,
              'reg': true,
            });
          }
          if (tok == 'tok-b') {
            return jsonResponse({
              'user': {'loggedIn': true, 'id': 'u2', 'name': 'bob'},
              'auth': true,
              'reg': true,
            });
          }
          return jsonResponse({'user': {'loggedIn': false}});
        }
        if (request.method == 'GET' && request.uri.path.startsWith('/api/work/')) {
          final id = int.parse(request.uri.path.split('/').last);
          final progress = accountProgress[tok]?[id];
          return jsonResponse({
            'id': id,
            'title': 'Work $id',
            if (tok.isNotEmpty) 'progress': progress,
          });
        }
        if (request.method == 'PUT' && request.uri.path == '/api/review') {
          if (rejectWrite) {
            return jsonResponse({'error': 'Forbidden'}, statusCode: 403);
          }
          final body = request.data as Map;
          final id = body['work_id'] as int;
          final next = body['progress'] as String;
          if (timeoutWrite) {
            // Simulate write actually succeeded on server right before client timed out.
            accountProgress[tok]![id] = next;
            timeoutWrite = false;
            throw DioException(
              requestOptions: request,
              type: DioExceptionType.receiveTimeout,
            );
          }
          accountProgress[tok]![id] = next;
          return jsonResponse({'ok': true});
        }
        if (request.uri.path.startsWith('/api/tracks/')) {
          return jsonResponse([]);
        }
        if (request.uri.path == '/api/review') {
          return jsonResponse({'reviews': [], 'page': 1, 'pageSize': 10, 'totalCount': 0});
        }
        return jsonResponse({'works': [], 'pagination': {'totalCount': 0}});
      });
      final api = _DelayedWriteApi(adapter, onWriteGate: () => holdWrite?.future)
        ..attachPrefs(prefs);
      final auth = AuthState(prefs, api: api);

      // 1. Guest sees "登录后标记" and tapping opens LoginScreen.
      await tester.pumpWidget(
        _wrapDetail(
          settings: settings,
          auth: auth,
          library: library,
          downloads: downloads,
          player: player,
          home: WorkDetailScreen(
            work: Work.fromJson({'id': 42, 'title': 'Work 42'}),
            api: api,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('登录后标记'), findsOneWidget);
      await tester.tap(find.text('收听状态'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      // 2. Login as alice -> reads "在听" for work 42.
      await tester.runAsync(() => auth.login('alice', 'secret123'));
      await tester.pumpWidget(
        _wrapDetail(
          settings: settings,
          auth: auth,
          library: library,
          downloads: downloads,
          player: player,
          home: WorkDetailScreen(
            work: Work.fromJson({'id': 42, 'title': 'Work 42'}),
            api: api,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('在听'), findsOneWidget);

      // 3. Server rejects write -> keeps previous status "在听".
      rejectWrite = true;
      await tester.tap(find.text('收听状态'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('听过'));
      await tester.pumpAndSettle();
      expect(find.text('在听'), findsOneWidget);
      expect(find.text('Forbidden'), findsOneWidget);
      rejectWrite = false;

      // 4. Timeout after server applied write -> read-back reconciles to "听过".
      timeoutWrite = true;
      await tester.tap(find.text('收听状态'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('听过'));
      await tester.pumpAndSettle();
      expect(find.text('听过'), findsOneWidget);

      // 5. Switch account to bob -> immediately clears alice's status and loads bob's "重听".
      await tester.runAsync(() => auth.login('bob', 'secret123'));
      await tester.pumpAndSettle();
      expect(find.text('重听'), findsOneWidget);
      expect(find.text('听过'), findsNothing);

      // 6. Start saving on work 42, then switch to work 99 before save completes -> work 99 stays unmarked.
      holdWrite = Completer<void>();
      await tester.tap(find.text('收听状态'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('搁置'));
      await tester.pump();
      await tester.pumpWidget(
        _wrapDetail(
          settings: settings,
          auth: auth,
          library: library,
          downloads: downloads,
          player: player,
          home: WorkDetailScreen(
            work: Work.fromJson({'id': 99, 'title': 'Work 99'}),
            api: api,
          ),
        ),
      );
      await tester.pumpAndSettle();
      holdWrite.complete();
      holdWrite = null;
      await tester.pumpAndSettle();
      expect(find.text('未标记'), findsOneWidget);
      expect(find.text('搁置'), findsNothing);

      // 7. Logout clears any account-bound status immediately.
      await tester.runAsync(() => auth.logout());
      await tester.pumpAndSettle();
      expect(find.text('登录后标记'), findsOneWidget);
      expect(find.text('未标记'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      player.dispose();
      downloads.dispose();
      library.dispose();
      auth.dispose();
      settings.dispose();
    },
  );
}

class _DelayedWriteApi extends ApiClient {
  _DelayedWriteApi(TestAdapter adapter, {this.onWriteGate})
    : super(adapter: adapter);

  final Future<void>? Function()? onWriteGate;

  @override
  Future<void> updateWorkProgress({
    required int workId,
    required ListeningStatus status,
  }) async {
    final gate = onWriteGate?.call();
    if (gate != null) await gate;
    return super.updateWorkProgress(workId: workId, status: status);
  }
}
