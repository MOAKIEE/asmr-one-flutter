import 'package:asmr_one/core/api/api_client.dart';
import 'package:asmr_one/core/models/track.dart';
import 'package:asmr_one/core/models/work.dart';
import 'package:asmr_one/core/storage/app_prefs.dart';
import 'package:asmr_one/l10n/app_localizations.dart';
import 'package:asmr_one/screens/player_screen.dart';
import 'package:asmr_one/screens/work_detail_screen.dart';
import 'package:asmr_one/state/auth_state.dart';
import 'package:asmr_one/state/download_state.dart';
import 'package:asmr_one/state/library_state.dart';
import 'package:asmr_one/state/listening_notes.dart';
import 'package:asmr_one/state/player_state.dart';
import 'package:asmr_one/state/settings_state.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client_test.dart' show TestAdapter, jsonResponse;
import 'download_state_test.dart' show DownloadLibrary;
import 'listening_notes_test.dart' show NotesLibrary;
import 'player_state_test.dart' show TestAudio, TestLibrary;

class _DetailTestLibrary extends DownloadLibrary {
  final documents = <String, Object?>{};
  @override
  bool isFavorite(int workId) => false;
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
  @override
  Future<Object?> readDocument(String key) async => documents[key];
  @override
  Future<void> writeDocument(String key, Object? value) async {
    if (value == null) {
      documents.remove(key);
    } else {
      documents[key] = value;
    }
  }
}

class _CoverlessApi extends ApiClient {
  _CoverlessApi({
    required this.workJson,
    required this.tracksJson,
    required this.subtitlesByHash,
  }) : super(
         adapter: TestAdapter((request) {
           if (request.uri.path.startsWith('/api/work/')) {
             return jsonResponse(workJson);
           }
           if (request.uri.path.startsWith('/api/tracks/')) {
             return jsonResponse(tracksJson);
           }
           return jsonResponse({'works': [], 'pagination': {'totalCount': 0}});
         }),
       );

  final Map<String, dynamic> workJson;
  final List<Map<String, dynamic>> tracksJson;
  final Map<String, String> subtitlesByHash;
  int fetchTracksCalls = 0;
  int fetchSubtitleCalls = 0;

  @override
  String coverUrl(int workId, {String type = 'main'}) => '';

  @override
  Future<List<TrackNode>> fetchTracks(int workId) {
    fetchTracksCalls++;
    return super.fetchTracks(workId);
  }

  @override
  Future<String> fetchSubtitle(TrackNode node) async {
    fetchSubtitleCalls++;
    return subtitlesByHash[node.hash] ?? '[00:01.00]Fallback';
  }
}

void main() {
  testWidgets(
    'selecting chapter 2 from work detail auto-matches chapter 2 subtitle and jumps to mid-track active line when cover is tapped',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({'ui.useCoverAccent': false});
      final prefs = await AppPrefs.load();
      final settings = SettingsState(prefs);
      final auth = AuthState(prefs);
      final library = _DetailTestLibrary();
      final downloads = DownloadState(library);

      final workJson = {
        'id': 88,
        'title': 'Whispering Forest',
        'circle': {'id': 1, 'name': 'Forest Circle'},
        'vas': const [],
        'tags': const [],
        'has_subtitle': true,
      };
      final tracksJson = [
        {
          'type': 'folder',
          'title': '本篇',
          'children': [
            {
              'type': 'audio',
              'title': '01 第一章.mp3',
              'hash': '88/1',
              'duration': 120.0,
              'mediaStreamUrl': 'https://example.invalid/1.mp3',
            },
            {
              'type': 'audio',
              'title': '02 第二章.mp3',
              'hash': '88/2',
              'duration': 120.0,
              'mediaStreamUrl': 'https://example.invalid/2.mp3',
            },
            {
              'type': 'text',
              'title': '01 第一章.lrc',
              'hash': '88/s1',
              'mediaDownloadUrl': 'https://example.invalid/s1.lrc',
            },
            {
              'type': 'text',
              'title': '02 第二章.lrc',
              'hash': '88/s2',
              'mediaDownloadUrl': 'https://example.invalid/s2.lrc',
            },
          ],
        },
      ];

      final ch2Lrc = List.generate(20, (i) {
        final sec = i * 5;
        final mm = (sec ~/ 60).toString().padLeft(2, '0');
        final ss = (sec % 60).toString().padLeft(2, '0');
        return '[$mm:$ss.00]第二章第${i + 1}句台词';
      }).join('\n');

      final api = _CoverlessApi(
        workJson: workJson,
        tracksJson: tracksJson,
        subtitlesByHash: {
          '88/s1': '[00:01.00]第一章开场',
          '88/s2': ch2Lrc,
        },
      );

      final audio = TestAudio()..duration = const Duration(minutes: 2);
      final player = PlayerState(
        settings: settings,
        library: library,
        audioPlayer: audio,
        api: api,
      );
      final notes = ListeningNotes(
        library,
        player,
        settings: settings,
        api: api,
        checkNetwork: () async => [ConnectivityResult.wifi],
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsState>.value(value: settings),
            ChangeNotifierProvider<AuthState>.value(value: auth),
            ChangeNotifierProvider<LibraryState>.value(value: library),
            ChangeNotifierProvider<DownloadState>.value(value: downloads),
            ChangeNotifierProvider<PlayerState>.value(value: player),
            ChangeNotifierProvider<ListeningNotes>.value(value: notes),
          ],
          child: MaterialApp(
            home: WorkDetailScreen(work: Work.fromJson(workJson), api: api),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.fetchTracksCalls, 1);

      // Scroll to and tap chapter 2.
      await tester.scrollUntilVisible(
        find.text('02 第二章'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('02 第二章'));
      await tester.pumpAndSettle();

      // Player opens on cover view; chapter 2 subtitle matched without refetching tracks!
      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(notes.showPlayerSubtitles, isFalse);
      expect(api.fetchTracksCalls, 1);
      expect(notes.subtitleName, '02 第二章.lrc');
      expect(notes.cues, hasLength(20));

      // Advance audio halfway through (00:52 -> cue index 10: "第二章第11句台词") while staying on cover.
      await audio.seek(const Duration(seconds: 52));
      await tester.pump();

      // Record controls & toggle button positions before switching.
      final toggleBefore = tester.getRect(
        find.byKey(const ValueKey('player-stage-toggle')),
      );
      final titleBefore = tester.getRect(find.text('02 第二章'));
      final sliderBefore = tester.getRect(find.byType(Slider));

      // Tap cover to switch in-place to subtitles.
      await tester.tap(find.byKey(const ValueKey('player-cover-tap')));
      await tester.pumpAndSettle();

      expect(notes.showPlayerSubtitles, isTrue);
      // Title, slider, and toggle button remain in the exact same vertical spot!
      expect(
        tester.getRect(find.byKey(const ValueKey('player-stage-toggle'))).top,
        closeTo(toggleBefore.top, 1.0),
      );
      expect(
        tester.getRect(find.text('02 第二章')).top,
        closeTo(titleBefore.top, 1.0),
      );
      expect(
        tester.getRect(find.byType(Slider)).top,
        closeTo(sliderBefore.top, 1.0),
      );

      // Mid-track active cue is visible without manual scrolling!
      expect(find.text('第二章第11句台词'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      notes.dispose();
      player.dispose();
      downloads.dispose();
      library.dispose();
      auth.dispose();
      settings.dispose();
    },
  );

  testWidgets(
    'small-screen 1.35x subtitle scroll, back-to-current-line, tap-to-seek, tools round-trip, and offset sync',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({'ui.useCoverAccent': false});
      final settings = SettingsState(await AppPrefs.load());
      final audio = TestAudio()..duration = const Duration(minutes: 3);
      final player = PlayerState(
        settings: settings,
        library: TestLibrary()..saved = 0,
        audioPlayer: audio,
      );
      await player.playWork(Work.fromJson({'id': 3, 'title': 'Compact Work'}), [
        const AudioTrack(
          node: TrackNode(
            type: 'audio',
            title: '01 Compact Chapter.mp3',
            hash: '3/c1',
            mediaStreamUrl: 'https://example.invalid/c1.mp3',
          ),
        ),
      ]);

      final library = NotesLibrary();
      final lrc = List.generate(30, (i) {
        final sec = i * 4;
        final mm = (sec ~/ 60).toString().padLeft(2, '0');
        final ss = (sec % 60).toString().padLeft(2, '0');
        return '[$mm:$ss.00]第${i + 1}句台词内容';
      }).join('\n');
      library.documents['subtitle:3:3/c1'] = {
        'name': '01 Compact Chapter.lrc',
        'source': lrc,
        'offsetMs': 0,
      };

      final notes = ListeningNotes(
        library,
        player,
        settings: settings,
        checkNetwork: () async => [ConnectivityResult.none],
      );
      await notes.reload();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsState>.value(value: settings),
            ChangeNotifierProvider<PlayerState>.value(value: player),
            ChangeNotifierProvider<LibraryState>.value(value: library),
            ChangeNotifierProvider<ListeningNotes>.value(value: notes),
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

      // Switch to subtitles.
      await tester.tap(find.byKey(const ValueKey('player-stage-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('显示封面'), findsOneWidget);
      expect(find.text('第1句台词内容'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Drag subtitle list manually -> stops follow and shows「回到当前句」.
      final subList = find.descendant(
        of: find.byKey(const ValueKey('player-subtitles')),
        matching: find.byType(ListView),
      );
      await tester.drag(subList, const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(find.text('回到当前句'), findsOneWidget);

      // Tap「回到当前句」-> resumes follow and hides the button.
      await tester.tap(find.text('回到当前句'));
      await tester.pumpAndSettle();
      expect(find.text('回到当前句'), findsNothing);

      // Tap line 2 (startMs = 4000ms) -> seeks audio to 4s and stays on subtitle view.
      await tester.tap(find.text('第2句台词内容'));
      await tester.pumpAndSettle();
      expect(audio.position, const Duration(seconds: 4));
      expect(notes.showPlayerSubtitles, isTrue);

      // Open ListeningToolsScreen via top-bar tune icon.
      await tester.tap(find.byTooltip('收听工具'));
      await tester.pumpAndSettle();
      expect(find.text('字幕设置'), findsOneWidget);

      // Adjust offset +0.5s, mark A point, add bookmark, then return to PlayerScreen.
      await tester.tap(find.byTooltip('+0.5s'));
      await tester.pumpAndSettle();
      expect(notes.offsetMs, 500);

      await tester.tap(find.text('A —'));
      await tester.pumpAndSettle();
      expect(player.loopStart, const Duration(seconds: 4));

      await tester.tap(find.text('书签'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('标记当前时间'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'Saved in tools');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(find.text('Saved in tools'), findsOneWidget);

      // Navigate back -> subtitle view and playback position preserved; tap line seeks with +500ms offset!
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(notes.showPlayerSubtitles, isTrue);
      expect(audio.position, const Duration(seconds: 4));

      await tester.tap(find.text('第2句台词内容'));
      await tester.pumpAndSettle();
      expect(audio.position, const Duration(milliseconds: 4500));

      // Toggle back to cover via same-position「显示封面」button.
      await tester.tap(find.byKey(const ValueKey('player-stage-toggle')));
      await tester.pumpAndSettle();
      expect(notes.showPlayerSubtitles, isFalse);
      expect(find.text('显示字幕'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      notes.dispose();
      player.dispose();
      library.dispose();
      settings.dispose();
    },
  );

  testWidgets(
    'player subtitle area shows ambiguous, offlineEmpty, and networkError states with retry and replace entries',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      SharedPreferences.setMockInitialValues({'ui.useCoverAccent': false});
      final settings = SettingsState(await AppPrefs.load());
      final audio = TestAudio()..duration = const Duration(minutes: 2);
      final library = NotesLibrary();

      // 1. Ambiguous state
      final ambigApi = _CoverlessApi(
        workJson: const {'id': 90, 'title': 'Ambiguous'},
        tracksJson: const [
          {
            'type': 'folder',
            'title': '本篇',
            'children': [
              {
                'type': 'audio',
                'title': '01.mp3',
                'hash': '90/a1',
                'mediaStreamUrl': 'https://example.invalid/90.mp3',
              },
            ],
          },
          {
            'type': 'folder',
            'title': '字幕',
            'children': [
              {
                'type': 'folder',
                'title': '简中',
                'children': [
                  {
                    'type': 'folder',
                    'title': '本篇',
                    'children': [
                      {
                        'type': 'text',
                        'title': '01.lrc',
                        'hash': '90/s_zh',
                        'mediaDownloadUrl': 'https://example.invalid/zh.lrc',
                      },
                    ],
                  },
                ],
              },
              {
                'type': 'folder',
                'title': '日文',
                'children': [
                  {
                    'type': 'folder',
                    'title': '本篇',
                    'children': [
                      {
                        'type': 'text',
                        'title': '01.lrc',
                        'hash': '90/s_ja',
                        'mediaDownloadUrl': 'https://example.invalid/ja.lrc',
                      },
                    ],
                  },
                ],
              },
            ],
          },
        ],
        subtitlesByHash: const {},
      );
      final player = PlayerState(
        settings: settings,
        library: TestLibrary()..saved = 0,
        audioPlayer: audio,
        api: ambigApi,
      );
      await player.playWork(Work.fromJson({'id': 90, 'title': 'Ambiguous'}), [
        const AudioTrack(
          folderPath: ['本篇'],
          node: TrackNode(
            type: 'audio',
            title: '01.mp3',
            hash: '90/a1',
            mediaStreamUrl: 'https://example.invalid/90.mp3',
          ),
        ),
      ]);
      final notes = ListeningNotes(
        library,
        player,
        settings: settings,
        api: ambigApi,
        checkNetwork: () async => [ConnectivityResult.wifi],
        languageResolver: () => 'en',
      );
      notes.cacheTrackTree(
        90,
        ambigApi.tracksJson.map(TrackNode.fromJson).toList(),
      );
      notes.showPlayerSubtitles = true;
      await notes.reload();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsState>.value(value: settings),
            ChangeNotifierProvider<PlayerState>.value(value: player),
            ChangeNotifierProvider<LibraryState>.value(value: library),
            ChangeNotifierProvider<ListeningNotes>.value(value: notes),
          ],
          child: const MaterialApp(home: PlayerScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('未能确定本章字幕'), findsOneWidget);
      expect(find.text('更换字幕'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 2. Offline empty state
      final offlineNotes = ListeningNotes(
        library,
        player,
        settings: settings,
        api: ambigApi,
        checkNetwork: () async => [ConnectivityResult.none],
      );
      offlineNotes.showPlayerSubtitles = true;
      await offlineNotes.reload();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsState>.value(value: settings),
            ChangeNotifierProvider<PlayerState>.value(value: player),
            ChangeNotifierProvider<LibraryState>.value(value: library),
            ChangeNotifierProvider<ListeningNotes>.value(value: offlineNotes),
          ],
          child: const MaterialApp(home: PlayerScreen()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('本机暂无本章字幕'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      offlineNotes.dispose();
      notes.dispose();
      player.dispose();
      library.dispose();
      settings.dispose();
    },
  );

  test('new subtitle and listening tools l10n keys exist in zh, ja, and en', () {
    const keys = [
      'notes.toolsTitle',
      'notes.subtitleSettings',
      'notes.replaceSubtitle',
      'notes.restoreAuto',
      'notes.source',
      'notes.sourceAuto',
      'notes.sourceManual',
      'notes.sourceManualWork',
      'notes.sourceManualLocal',
      'notes.sourceNone',
      'notes.offsetHint',
      'notes.importLocal',
      'player.showSubtitles',
      'player.showCover',
      'player.backToCurrentLine',
      'subtitle.matching',
      'subtitle.empty',
      'subtitle.ambiguous',
      'subtitle.offlineEmpty',
      'subtitle.networkError',
      'subtitle.parseError',
    ];
    final zh = L10n.forLocale(const Locale('zh', 'CN'));
    final ja = L10n.forLocale(const Locale('ja', 'JP'));
    final en = L10n.forLocale(const Locale('en', 'US'));
    for (final key in keys) {
      expect(zh(key), isNot(key), reason: 'Missing zh key: $key');
      expect(ja(key), isNot(key), reason: 'Missing ja key: $key');
      expect(en(key), isNot(key), reason: 'Missing en key: $key');
      expect(ja(key), isNot(zh(key)), reason: 'Untranslated ja key: $key');
      expect(en(key), isNot(zh(key)), reason: 'Untranslated en key: $key');
    }
  });
}
