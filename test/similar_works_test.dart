import 'dart:async';

import 'package:asmr_one/core/api/api_client.dart';
import 'package:asmr_one/core/models/work.dart';
import 'package:asmr_one/core/storage/app_prefs.dart';
import 'package:asmr_one/core/storage/library_db.dart';
import 'package:asmr_one/l10n/app_localizations.dart';
import 'package:asmr_one/screens/login_screen.dart';
import 'package:asmr_one/screens/similar_works_screen.dart';
import 'package:asmr_one/screens/work_detail_screen.dart';
import 'package:asmr_one/state/auth_state.dart';
import 'package:asmr_one/state/download_state.dart';
import 'package:asmr_one/state/library_state.dart';
import 'package:asmr_one/state/player_state.dart';
import 'package:asmr_one/state/settings_state.dart';
import 'package:asmr_one/state/work_feed.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client_test.dart' show TestAdapter, jsonResponse;
import 'download_state_test.dart' show DownloadLibrary;
import 'player_state_test.dart' show TestAudio;

class _SimilarLibrary extends DownloadLibrary {
  @override
  bool isFavorite(int workId) => false;

  @override
  Set<int> get downloadedWorkIds => const {};

  @override
  List<LocalPlaylistRow> get localPlaylists => const [];

  @override
  Future<int> progressFor(String hash) async => 0;

  @override
  Future<void> recordHistory(Work work) async {}

  @override
  Future<void> saveProgress({
    required String hash,
    required int workId,
    required int positionMs,
    required int durationMs,
  }) async {}
}

class _StubSimilarApi extends ApiClient {
  _StubSimilarApi(this._onSimilar);

  final Future<WorksPage> Function(int workId, int page, bool subtitle)
  _onSimilar;

  @override
  String coverUrl(int workId, {String type = 'main'}) => '';

  @override
  Future<WorksPage> fetchSimilarWorks(
    int workId, {
    int page = 1,
    bool subtitle = false,
  }) => _onSimilar(workId, page, subtitle);

  @override
  Future<Work> fetchWork(int id) async =>
      Work.fromJson({'id': id, 'title': 'Source Work'});
}

Widget _wrapApp({
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
  test(
    'fetchSimilarWorks sends recommender payload for both guest and signed-in users and uses server pagination',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await AppPrefs.load();
      final adapter = TestAdapter((request) {
        return jsonResponse({
          'works': [
            {'id': 201, 'title': 'Neighbor A', 'nsfw': false},
            {'id': 202, 'title': 'Neighbor B', 'nsfw': true},
          ],
          'pagination': {'currentPage': 2, 'pageSize': 2, 'totalCount': 5},
        });
      });
      final api = ApiClient(adapter: adapter)..attachPrefs(prefs);

      // Guest request
      final guestPage = await api.fetchSimilarWorks(100, page: 2, subtitle: true);
      expect(guestPage.works.map((w) => w.id), [201, 202]);
      expect(guestPage.page, 2);
      expect(guestPage.pageSize, 2);
      expect(guestPage.totalCount, 5);
      expect(guestPage.maxPage, 3);
      final guestReq = adapter.requests.last;
      expect(guestReq.method, 'POST');
      expect(guestReq.uri.path, '/api/recommender/item-neighbors');
      expect(guestReq.headers.containsKey('Authorization'), isFalse);
      expect(guestReq.data, {
        'keyword': '',
        'itemId': '100',
        'page': 2,
        'subtitle': 1,
        'localSubtitledWorks': const <Object>[],
        'withPlaylistStatus': const <Object>[],
      });

      // Signed-in request
      prefs.token = 'jwt-token';
      await api.fetchSimilarWorks(100, page: 1, subtitle: false);
      final authReq = adapter.requests.last;
      expect(authReq.headers['Authorization'], 'Bearer jwt-token');
      expect((authReq.data as Map)['subtitle'], 0);
    },
  );

  test(
    'WorkFeed deduplicates within and across pages while preserving server order',
    () async {
      final feed = WorkFeed((page, _) async {
        if (page == 1) {
          return WorksPage(
            works: [
              Work.fromJson({'id': 10, 'title': 'First'}),
              Work.fromJson({'id': 20, 'title': 'Second'}),
              Work.fromJson({'id': 10, 'title': 'Dup on page 1'}),
            ],
            page: 1,
            pageSize: 3,
            totalCount: 6,
          );
        }
        return WorksPage(
          works: [
            Work.fromJson({'id': 20, 'title': 'Dup on page 2'}),
            Work.fromJson({'id': 30, 'title': 'Third'}),
            Work.fromJson({'id': 5, 'title': 'Fourth'}),
          ],
          page: 2,
          pageSize: 3,
          totalCount: 6,
        );
      });
      addTearDown(feed.dispose);

      await feed.load();
      expect(feed.items.map((w) => w.id), [10, 20]);
      expect(feed.hasMore, isTrue);

      await feed.loadMore();
      expect(feed.items.map((w) => w.id), [10, 20, 30, 5]);
      expect(feed.hasMore, isFalse);
    },
  );

  test(
    'WorkFeed with SFW filter advances past fully-filtered page 1 to show visible page 2',
    () async {
      final requested = <int>[];
      final feed = WorkFeed(
        (page, _) async {
          requested.add(page);
          if (page == 1) {
            return WorksPage(
              works: [
                Work.fromJson({'id': 1, 'title': 'Adult 1', 'nsfw': true}),
                Work.fromJson({'id': 2, 'title': 'Adult 2', 'nsfw': true}),
              ],
              page: 1,
              pageSize: 2,
              totalCount: 4,
            );
          }
          return WorksPage(
            works: [
              Work.fromJson({'id': 3, 'title': 'Safe 3', 'nsfw': false}),
              Work.fromJson({'id': 4, 'title': 'Adult 4', 'nsfw': true}),
            ],
            page: 2,
            pageSize: 2,
            totalCount: 4,
          );
        },
        filter: (work) => !work.nsfw,
      );
      addTearDown(feed.dispose);

      await feed.load();
      expect(requested, [1, 2]);
      expect(feed.isEmpty, isFalse);
      expect(feed.items.map((w) => w.id), [3]);
      expect(feed.hasMore, isFalse);
    },
  );

  testWidgets(
    'WorkDetailScreen loads tracks without calling recommender until user opens SimilarWorksScreen',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'ui.locale': 'zh-CN',
        'ui.useCoverAccent': false,
      });
      final prefs = await AppPrefs.load();
      final settings = SettingsState(prefs);
      final auth = AuthState(prefs);
      final library = _SimilarLibrary();
      final downloads = DownloadState(library);
      final player = PlayerState(
        settings: settings,
        library: library,
        audioPlayer: TestAudio(),
      );

      var similarRequests = 0;
      final api = ApiClient(
        adapter: TestAdapter((request) {
          if (request.uri.path == '/api/work/42') {
            return jsonResponse({
              'id': 42,
              'title': 'Current Work',
              'circle_id': 7,
              'name': 'Circle A',
            });
          }
          if (request.uri.path == '/api/tracks/42') {
            return jsonResponse([
              {
                'type': 'audio',
                'title': '01.mp3',
                'hash': '42/0',
                'duration': 60.0,
                'mediaStreamUrl': 'https://example.invalid/42.mp3',
              },
            ]);
          }
          if (request.uri.path == '/api/recommender/item-neighbors') {
            similarRequests++;
            return jsonResponse({
              'works': [
                {'id': 99, 'title': 'Similar Neighbor', 'nsfw': false},
              ],
              'pagination': {'currentPage': 1, 'pageSize': 20, 'totalCount': 1},
            });
          }
          return jsonResponse({'works': [], 'pagination': {'totalCount': 0}});
        }),
      );

      await tester.pumpWidget(
        _wrapApp(
          settings: settings,
          auth: auth,
          library: library,
          downloads: downloads,
          player: player,
          home: WorkDetailScreen(
            work: Work.fromJson({'id': 42, 'title': 'Current Work'}),
            api: api,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Before tapping Similar Works, recommender API must not be called.
      expect(similarRequests, 0);

      await tester.scrollUntilVisible(
        find.text('相似作品'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(similarRequests, 0);

      await tester.tap(find.text('相似作品'));
      await tester.pumpAndSettle();
      expect(similarRequests, 1);
      expect(find.text('Similar Neighbor'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      player.dispose();
      downloads.dispose();
      library.dispose();
      auth.dispose();
      settings.dispose();
    },
  );

  testWidgets(
    'SimilarWorksScreen keeps latest subtitle selection when earlier request finishes last',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'ui.locale': 'zh-CN',
        'ui.useCoverAccent': false,
      });
      final prefs = await AppPrefs.load();
      final settings = SettingsState(prefs);
      final auth = AuthState(prefs);
      final library = _SimilarLibrary();
      final downloads = DownloadState(library);
      final player = PlayerState(
        settings: settings,
        library: library,
        audioPlayer: TestAudio(),
      );

      final firstReq = Completer<WorksPage>();
      final secondReq = Completer<WorksPage>();
      final thirdReq = Completer<WorksPage>();
      var call = 0;

      final api = _StubSimilarApi((workId, page, subtitle) {
        call++;
        if (call == 1) return firstReq.future;
        if (call == 2) return secondReq.future;
        return thirdReq.future;
      });

      await tester.pumpWidget(
        _wrapApp(
          settings: settings,
          auth: auth,
          library: library,
          downloads: downloads,
          player: player,
          home: SimilarWorksScreen(
            work: Work.fromJson({'id': 42, 'title': 'Origin'}),
            api: api,
          ),
        ),
      );
      await tester.pump();

      // Toggle subtitle ON -> call 2, then OFF -> call 3.
      await tester.tap(find.byType(FilterChip));
      await tester.pump();
      await tester.tap(find.byType(FilterChip));
      await tester.pump();
      expect(call, 3);

      // Complete latest request first, then stale requests last.
      thirdReq.complete(
        WorksPage(
          works: [Work.fromJson({'id': 3, 'title': 'Latest Selection'})],
          page: 1,
          pageSize: 20,
          totalCount: 1,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Latest Selection'), findsOneWidget);

      secondReq.complete(
        WorksPage(
          works: [Work.fromJson({'id': 2, 'title': 'Stale Subtitle On'})],
          page: 1,
          pageSize: 20,
          totalCount: 1,
        ),
      );
      firstReq.complete(
        WorksPage(
          works: [Work.fromJson({'id': 1, 'title': 'Stale Initial'})],
          page: 1,
          pageSize: 20,
          totalCount: 1,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Latest Selection'), findsOneWidget);
      expect(find.text('Stale Subtitle On'), findsNothing);
      expect(find.text('Stale Initial'), findsNothing);

      await tester.pumpWidget(const SizedBox());
      player.dispose();
      downloads.dispose();
      library.dispose();
      auth.dispose();
      settings.dispose();
    },
  );

  testWidgets(
    'SimilarWorksScreen handles empty state, auth-required login entry, and timeout retry',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'ui.locale': 'zh-CN',
        'ui.useCoverAccent': false,
      });
      final prefs = await AppPrefs.load();
      final settings = SettingsState(prefs);
      final auth = AuthState(prefs);
      final library = _SimilarLibrary();
      final downloads = DownloadState(library);
      final player = PlayerState(
        settings: settings,
        library: library,
        audioPlayer: TestAudio(),
      );

      // 1. Empty state
      await tester.pumpWidget(
        _wrapApp(
          settings: settings,
          auth: auth,
          library: library,
          downloads: downloads,
          player: player,
          home: SimilarWorksScreen(
            work: Work.fromJson({'id': 1, 'title': 'Empty Source'}),
            api: _StubSimilarApi((_, _, _) async => WorksPage.empty),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('暂无相似作品'), findsOneWidget);

      // 2. Auth required shows login button
      await tester.pumpWidget(
        _wrapApp(
          settings: settings,
          auth: auth,
          library: library,
          downloads: downloads,
          player: player,
          home: SimilarWorksScreen(
            work: Work.fromJson({'id': 2, 'title': 'Auth Source'}),
            api: _StubSimilarApi(
              (_, _, _) async => throw ApiException(
                '需要登录后才能使用该功能，请先在「我的」中登录账号。',
                statusCode: 401,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('登录'), findsOneWidget);
      await tester.tap(find.text('登录'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      // 3. Timeout can retry on current page
      var shouldTimeout = true;
      final timeoutApi = ApiClient(
        adapter: TestAdapter((request) {
          if (shouldTimeout) {
            shouldTimeout = false;
            throw DioException(
              requestOptions: request,
              type: DioExceptionType.receiveTimeout,
            );
          }
          return jsonResponse({
            'works': [
              {'id': 55, 'title': 'Recovered After Retry', 'nsfw': false},
            ],
            'pagination': {'currentPage': 1, 'pageSize': 20, 'totalCount': 1},
          });
        }),
      );
      await tester.pumpWidget(
        _wrapApp(
          settings: settings,
          auth: auth,
          library: library,
          downloads: downloads,
          player: player,
          home: SimilarWorksScreen(
            work: Work.fromJson({'id': 3, 'title': 'Timeout Source'}),
            api: timeoutApi,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('连接超时，请稍后重试。'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('Recovered After Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      player.dispose();
      downloads.dispose();
      library.dispose();
      auth.dispose();
      settings.dispose();
    },
  );
}
