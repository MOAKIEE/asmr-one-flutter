import 'package:asmr_one/core/api/api_client.dart';
import 'package:asmr_one/core/models/track.dart';
import 'package:asmr_one/core/models/work.dart';
import 'package:asmr_one/core/storage/app_prefs.dart';
import 'package:asmr_one/core/storage/library_db.dart';
import 'package:asmr_one/screens/player_screen.dart';
import 'package:asmr_one/screens/work_detail_screen.dart';
import 'package:asmr_one/state/auth_state.dart';
import 'package:asmr_one/state/download_state.dart';
import 'package:asmr_one/state/library_state.dart';
import 'package:asmr_one/state/player_state.dart';
import 'package:asmr_one/state/settings_state.dart';
import 'package:asmr_one/widgets/mini_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client_test.dart' show TestAdapter, jsonResponse;
import 'auth_state_test.dart' show SessionApi;
import 'download_state_test.dart' show DownloadLibrary;
import 'player_state_test.dart' show TestAudio, TestLibrary;

class _RetryableAudio extends TestAudio {
  bool failNextSetSources = false;

  @override
  Future<Duration?> setAudioSources(
    List<ja.AudioSource> sources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ja.ShuffleOrder? shuffleOrder,
  }) {
    if (failNextSetSources) {
      failNextSetSources = false;
      throw StateError('transient error');
    }
    return super.setAudioSources(
      sources,
      preload: preload,
      initialIndex: initialIndex,
      initialPosition: initialPosition,
      shuffleOrder: shuffleOrder,
    );
  }
}

class _CoverlessSessionApi extends SessionApi {
  @override
  String coverUrl(int workId, {String type = 'main'}) => '';
}

class _DetailTestLibrary extends DownloadLibrary {
  @override
  bool isFavorite(int workId) => false;

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

class _TestPlayerState extends PlayerState {
  _TestPlayerState(SettingsState settings, TestAudio audio)
    : super(
        settings: settings,
        library: TestLibrary(),
        audioPlayer: audio,
      );

  @override
  PlayItem? get currentItem {
    final item = super.currentItem;
    return item == null
        ? null
        : PlayItem(
            workId: item.workId,
            workTitle: item.workTitle,
            title: item.title,
            url: item.url,
            coverUrl: '',
            folderLabel: item.folderLabel,
          );
  }
}

void main() {
  testWidgets(
    'player sheets do not overflow on 360x640 at 1.35x and queue close keeps playback',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({'ui.useCoverAccent': false});
      final prefs = await AppPrefs.load();
      final settings = SettingsState(prefs);
      final library = _DetailTestLibrary();
      final audio = TestAudio();
      final player = _TestPlayerState(settings, audio);
      await player.playLocalFiles(
        Work.fromJson({'id': 1, 'title': 'Calm Night Whisper'}),
        {'h1': '/track_01.mp3', 'h2': '/track_02.flac'},
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsState>.value(value: settings),
            ChangeNotifierProvider<LibraryState>.value(value: library),
            ChangeNotifierProvider<PlayerState>.value(value: player),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.35),
              ),
              child: child!,
            ),
            home: const PlayerScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('track_01'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byIcon(Icons.speed_rounded));
      await tester.pumpAndSettle();
      expect(find.text('1.25x'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('1.25x'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.bedtime_outlined));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.music_off), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.queue_music_rounded));
      await tester.pumpAndSettle();
      expect(find.text('track_02'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(player.queue, hasLength(2));
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      player.dispose();
      library.dispose();
      settings.dispose();
    },
  );

  testWidgets(
    'work detail renders non-audio .lrc attachment without folder icon on small screen',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({'ui.useCoverAccent': false});
      final prefs = await AppPrefs.load();
      final settings = SettingsState(prefs);
      final auth = AuthState(prefs);
      final library = _DetailTestLibrary();
      final downloads = DownloadState(library);
      final player = _TestPlayerState(settings, TestAudio());

      final workJson = {
        'id': 42,
        'title': 'Very Long Rainy Evening Title For Detail Header Test',
        'circle': {'id': 7, 'name': 'Rainy Studio'},
        'vas': [
          {'id': 'v1', 'name': 'CV Sample'},
        ],
        'tags': [
          {'id': 1, 'name': 'Binaural', 'i18n': {'zh-cn': {'name': '双声道'}}},
        ],
        'rate_average_2dp': 4.8,
        'rate_count': 120,
        'dl_count': 5400,
        'price': 0,
        'nsfw': false,
        'has_subtitle': true,
        'release': '2025-05-01',
        'create_date': '2026-01-01',
      };
      final tracksJson = [
        {
          'type': 'folder',
          'title': '01 Main',
          'children': [
            {
              'type': 'audio',
              'title': '01 Whisper.mp3',
              'hash': 'h1',
              'duration': 120.0,
              'mediaStreamUrl': 'https://example.invalid/1.mp3',
            },
            {
              'type': 'text',
              'title': '01 Whisper.lrc',
            },
          ],
        },
        {
          'type': 'other',
          'title': 'readme.txt',
        },
      ];

      final api = ApiClient(
        adapter: TestAdapter((request) {
          if (request.uri.path == '/api/work/42') {
            return jsonResponse(workJson);
          }
          if (request.uri.path == '/api/tracks/42') {
            return jsonResponse(tracksJson);
          }
          return jsonResponse({'works': [], 'pagination': {'totalCount': 0}});
        }),
      );

      final work = Work.fromJson(workJson);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsState>.value(value: settings),
            ChangeNotifierProvider<AuthState>.value(value: auth),
            ChangeNotifierProvider<LibraryState>.value(value: library),
            ChangeNotifierProvider<DownloadState>.value(value: downloads),
            ChangeNotifierProvider<PlayerState>.value(value: player),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.35),
              ),
              child: child!,
            ),
            home: WorkDetailScreen(work: work, api: api),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('readme.txt'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('01 Main'), findsOneWidget);
      expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
      expect(find.byIcon(Icons.subtitles_outlined), findsOneWidget);
      expect(find.byIcon(Icons.description_outlined), findsOneWidget);
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
    'player screen shows refreshTokens error with retry and renders initial restored position immediately',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({
        'auth.token': 'user-a',
        'ui.useCoverAccent': false,
      });
      final prefs = await AppPrefs.load();
      final settings = SettingsState(prefs);
      final library = _DetailTestLibrary();
      final api = _CoverlessSessionApi();
      final audio = _RetryableAudio()..duration = const Duration(minutes: 2);
      final player = PlayerState(
        settings: settings,
        library: library,
        audioPlayer: audio,
        api: api,
        readSession: (_) async => {
          'playerSession': {
            'index': 0,
            'position': 23000,
            'shuffle': false,
            'loop': 0,
          },
          'playerQueue': [
            {
              'workId': 8,
              'workTitle': 'Restored',
              'title': 'Track.mp3',
              'hash': '8/0',
              'url': 'https://api.asmr-200.com/api/media/stream/8/0',
              'coverUrl': '',
            },
          ],
        },
      );
      final auth = AuthState(
        prefs,
        api: api,
        onTokenChanged: player.refreshTokens,
      );
      await auth.bootstrap();
      await player.restoreSession();

      // Verify MiniPlayer shows non-zero progress on its initial frame.
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsState>.value(value: settings),
            ChangeNotifierProvider<LibraryState>.value(value: library),
            ChangeNotifierProvider<PlayerState>.value(value: player),
          ],
          child: const MaterialApp(home: Scaffold(body: MiniPlayer())),
        ),
      );
      await tester.pump();
      final miniBar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(miniBar.value, closeTo(23 / 120, 0.01));

      // Verify PlayerScreen shows 0:23 immediately on its initial frame.
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsState>.value(value: settings),
            ChangeNotifierProvider<LibraryState>.value(value: library),
            ChangeNotifierProvider<PlayerState>.value(value: player),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(1.35),
              ),
              child: child!,
            ),
            home: const PlayerScreen(),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('0:23'), findsOneWidget);
      expect(find.text('2:00'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Force token refresh failure on logout -> error banner appears; retry succeeds and clears it.
      audio.failNextSetSources = true;
      await auth.logout();
      await tester.pumpAndSettle();
      expect(find.text('更新播放地址失败，请重试。'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await tester.pumpAndSettle();
      expect(find.text('更新播放地址失败，请重试。'), findsNothing);
      expect(player.error, isNull);
      expect(
        (audio.sources.single as ja.UriAudioSource).uri.queryParameters['token'],
        '',
      );
      expect(tester.takeException(), isNull);

      // Verify playing a fresh track still works cleanly after retry.
      await player.playWork(
        Work.fromJson({'id': 9, 'title': 'Next'}),
        [
          TrackNode.fromJson({
            'type': 'audio',
            'hash': '9/0',
            'title': '01.mp3',
            'mediaStreamUrl': 'https://cdn.example/01.mp3',
          }).flatten().single,
        ],
      );
      await tester.pumpAndSettle();
      expect(player.error, isNull);

      await tester.pumpWidget(const SizedBox());
      player.dispose();
      auth.dispose();
      library.dispose();
      settings.dispose();
    },
  );
}
