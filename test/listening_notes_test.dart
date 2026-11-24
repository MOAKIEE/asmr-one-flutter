import 'dart:async';

import 'package:asmr_one/core/api/api_client.dart';
import 'package:asmr_one/core/models/subtitle_matcher.dart';
import 'package:asmr_one/core/models/track.dart';
import 'package:asmr_one/core/models/work.dart';
import 'package:asmr_one/core/storage/app_prefs.dart';
import 'package:asmr_one/state/library_state.dart';
import 'package:asmr_one/state/listening_notes.dart';
import 'package:asmr_one/state/player_state.dart';
import 'package:asmr_one/state/settings_state.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_state_test.dart' show TestAudio, TestLibrary;

class NotesLibrary extends ChangeNotifier implements LibraryState {
  final documents = <String, Object?>{};
  int _docsVersion = 0;

  @override
  int get documentsVersion => _docsVersion;

  void bumpDocumentsVersion() {
    _docsVersion++;
    notifyListeners();
  }

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

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubSubtitleApi extends ApiClient {
  _StubSubtitleApi({
    this.tracksByWork = const {},
    this.subtitleHandler,
    this.onFetchTracks,
  });

  final Map<int, List<TrackNode>> tracksByWork;
  final Future<String> Function(TrackNode node)? subtitleHandler;
  final Future<List<TrackNode>> Function(int workId)? onFetchTracks;
  int fetchTracksCalls = 0;
  int fetchSubtitleCalls = 0;

  @override
  Future<List<TrackNode>> fetchTracks(int workId) {
    fetchTracksCalls++;
    if (onFetchTracks != null) return onFetchTracks!(workId);
    return Future.value(tracksByWork[workId] ?? const []);
  }

  @override
  Future<String> fetchSubtitle(TrackNode node) {
    fetchSubtitleCalls++;
    if (subtitleHandler != null) return subtitleHandler!(node);
    return Future.value('[00:01.00]Subtitle for ${node.title}');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'bookmarks and legacy manual subtitles persist per track and survive reopening',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsState(await AppPrefs.load());
      final player = PlayerState(
        settings: settings,
        library: TestLibrary(),
        audioPlayer: TestAudio(),
      );
      await player.playLocalFiles(Work.fromJson({'id': 1}), {'a': '/a.mp3'});
      final library = NotesLibrary();
      final api = _StubSubtitleApi();
      final notes = ListeningNotes(
        library,
        player,
        settings: settings,
        api: api,
        checkNetwork: () async => [ConnectivityResult.wifi],
      );
      await notes.reload();
      await notes.addBookmark('a note', positionMs: 9000);
      await notes.importSubtitle('captions.lrc', '[00:01.00]Hello');
      await notes.setOffset(-500);
      notes.dispose();

      // Simulate legacy stored manual subtitle without `origin` field.
      library.documents['subtitle:1:a'] = {
        'name': 'captions.lrc',
        'source': '[00:01.00]Hello',
        'offsetMs': -500,
      };
      final restored = ListeningNotes(
        library,
        player,
        settings: settings,
        api: api,
        checkNetwork: () async => [ConnectivityResult.wifi],
      );
      await restored.reload();
      expect(restored.bookmarks.single.positionMs, 9000);
      expect(restored.bookmarks.single.note, 'a note');
      expect(restored.offsetMs, -500);
      expect(restored.cues.single.text, 'Hello');
      expect(restored.subtitleSource, SubtitleSource.manual);
      await expectLater(
        restored.importSubtitle('bad.srt', 'invalid'),
        throwsFormatException,
      );
      expect(restored.cues.single.text, 'Hello');
      await restored.editBookmark(restored.bookmarks.single, 'updated');
      expect(restored.bookmarks.single.note, 'updated');

      // Unrelated library notification must NOT clear loaded subtitles.
      library.notifyListeners();
      await Future<void>.delayed(Duration.zero);
      expect(restored.cues.single.text, 'Hello');

      await player.playLocalFiles(Work.fromJson({'id': 1}), {'b': '/b.mp3'});
      await restored.reload();
      expect(restored.bookmarks, isEmpty);
      expect(restored.cues, isEmpty);

      restored.dispose();
      library.dispose();
      player.dispose();
      settings.dispose();
    },
  );

  test(
    'A -> B -> A race condition ignores late first-A completion and clears immediately on empty track B',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsState(await AppPrefs.load());
      final player = PlayerState(
        settings: settings,
        library: TestLibrary(),
        audioPlayer: TestAudio(),
      );
      final library = NotesLibrary();

      final firstACompleter = Completer<String>();
      final secondACompleter = Completer<String>();
      var aFetchCount = 0;

      final workTracks = [
        TrackNode(
          type: 'folder',
          title: '本篇',
          children: [
            const TrackNode(
              type: 'audio',
              title: '01 A.mp3',
              hash: '10/a',
              mediaStreamUrl: 'https://example.invalid/a.mp3',
            ),
            const TrackNode(
              type: 'audio',
              title: '02 B.mp3',
              hash: '10/b',
              mediaStreamUrl: 'https://example.invalid/b.mp3',
            ),
            const TrackNode(
              type: 'text',
              title: '01 A.lrc',
              hash: '10/sub_a',
              mediaDownloadUrl: 'https://example.invalid/a.lrc',
            ),
          ],
        ),
      ];

      final api = _StubSubtitleApi(
        tracksByWork: {10: workTracks},
        subtitleHandler: (node) {
          aFetchCount++;
          return aFetchCount == 1
              ? firstACompleter.future
              : secondACompleter.future;
        },
      );

      final notes = ListeningNotes(
        library,
        player,
        settings: settings,
        api: api,
        checkNetwork: () async => [ConnectivityResult.wifi],
      );

      final work = Work.fromJson({'id': 10, 'title': 'Race Work'});
      final flat = workTracks.expand((n) => n.flatten()).toList();
      await player.playWork(work, flat, startIndex: 0);
      // Let A's first fetch start.
      await Future<void>.delayed(Duration.zero);
      expect(aFetchCount, 1);

      // Switch to B (no subtitle): immediately clears and ends in empty.
      await player.seekToIndex(1);
      expect(notes.cues, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(notes.subtitleStatus, SubtitleStatus.empty);

      // Switch back to A: starts second request for A.
      await player.seekToIndex(0);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(aFetchCount, 2);

      // Second A completes FIRST.
      secondACompleter.complete('[00:01.00]Second A winner');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(notes.cues.single.text, 'Second A winner');
      expect(
        (library.documents['matchedSubtitle:10:10/a'] as Map)['source'],
        '[00:01.00]Second A winner',
      );

      // Deliberately complete FIRST A LAST: must NOT overwrite UI or cache!
      firstACompleter.complete('[00:01.00]Stale First A');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(notes.cues.single.text, 'Second A winner');
      expect(
        (library.documents['matchedSubtitle:10:10/a'] as Map)['source'],
        '[00:01.00]Second A winner',
      );

      notes.dispose();
      library.dispose();
      player.dispose();
      settings.dispose();
    },
  );

  test(
    'merges concurrent fetchTracks requests per work and caches corrupt attachments nowhere',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsState(await AppPrefs.load());
      final player = PlayerState(
        settings: settings,
        library: TestLibrary(),
        audioPlayer: TestAudio(),
      );
      final library = NotesLibrary();

      final tracksCompleter = Completer<List<TrackNode>>();
      final api = _StubSubtitleApi(
        onFetchTracks: (_) => tracksCompleter.future,
        subtitleHandler: (_) async => 'corrupt not a subtitle',
      );
      final notes = ListeningNotes(
        library,
        player,
        settings: settings,
        api: api,
        checkNetwork: () async => [ConnectivityResult.wifi],
      );

      // Concurrent getTrackIndex calls for the same workId collapse into one fetchTracks.
      final f1 = notes.getTrackIndex(77);
      final f2 = notes.getTrackIndex(77);
      expect(api.fetchTracksCalls, 1);

      tracksCompleter.complete([
        const TrackNode(
          type: 'audio',
          title: '01.mp3',
          hash: '77/a1',
          mediaStreamUrl: 'https://example.invalid/77.mp3',
        ),
        const TrackNode(
          type: 'text',
          title: '01.lrc',
          hash: '77/s1',
          mediaDownloadUrl: 'https://example.invalid/77.lrc',
        ),
      ]);
      final indices = await Future.wait([f1, f2]);
      expect(identical(indices[0], indices[1]), isTrue);

      // Playing the track hits the corrupt subtitle: parseError and NOT cached!
      await player.playWork(Work.fromJson({'id': 77, 'title': 'Corrupt'}), [
        indices[0].audioTracks.single,
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(notes.subtitleStatus, SubtitleStatus.parseError);
      expect(notes.cues, isEmpty);
      expect(library.documents.containsKey('matchedSubtitle:77:77/a1'), isFalse);

      notes.dispose();
      library.dispose();
      player.dispose();
      settings.dispose();
    },
  );

  test(
    'offline cache hit loads matchedSubtitle without network; offline first play shows offlineEmpty',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsState(await AppPrefs.load());
      final player = PlayerState(
        settings: settings,
        library: TestLibrary(),
        audioPlayer: TestAudio(),
      );
      final library = NotesLibrary();
      library.documents['matchedSubtitle:5:5/cached'] = {
        'attachmentId': '5/sub1',
        'name': '01.lrc',
        'source': '[00:02.00]Offline cached line',
        'language': 'zh-hans',
        'ruleVersion': SubtitleMatcher.ruleVersion,
        'offsetMs': 1000,
      };
      final api = _StubSubtitleApi();
      final notes = ListeningNotes(
        library,
        player,
        settings: settings,
        api: api,
        checkNetwork: () async => [ConnectivityResult.none],
        languageResolver: () => 'zh-hans',
      );

      await player.playLocalFiles(Work.fromJson({'id': 5, 'title': 'Offline'}), {
        '5/cached': '/cached.mp3',
        '5/fresh': '/fresh.mp3',
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(notes.subtitleStatus, SubtitleStatus.loaded);
      expect(notes.subtitleSource, SubtitleSource.auto);
      expect(notes.cues.single.text, 'Offline cached line');
      expect(notes.offsetMs, 1000);
      expect(api.fetchTracksCalls, 0);

      // Switch to uncached track while offline -> offlineEmpty.
      await player.seekToIndex(1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(notes.subtitleStatus, SubtitleStatus.offlineEmpty);
      expect(notes.cues, isEmpty);
      expect(api.fetchTracksCalls, 0);

      notes.dispose();
      library.dispose();
      player.dispose();
      settings.dispose();
    },
  );

  test(
    'language switch re-evaluates auto-match; manual replace affects only that track and restoreAuto recovers auto-match',
    () async {
      SharedPreferences.setMockInitialValues({'ui.locale': 'zh'});
      final settings = SettingsState(await AppPrefs.load());
      final player = PlayerState(
        settings: settings,
        library: TestLibrary(),
        audioPlayer: TestAudio(),
      );
      final library = NotesLibrary();

      final tracks = [
        TrackNode(
          type: 'folder',
          title: 'MP3',
          children: [
            const TrackNode(
              type: 'audio',
              title: '01 耳かき.mp3',
              hash: '9/a1',
              mediaStreamUrl: 'https://example.invalid/a1.mp3',
            ),
            const TrackNode(
              type: 'audio',
              title: '02 添い寝.mp3',
              hash: '9/a2',
              mediaStreamUrl: 'https://example.invalid/a2.mp3',
            ),
          ],
        ),
        TrackNode(
          type: 'folder',
          title: '字幕',
          children: [
            TrackNode(
              type: 'folder',
              title: '简中',
              children: [
                const TrackNode(
                  type: 'text',
                  title: '01 耳かき.srt',
                  hash: '9/s1_zh',
                  mediaDownloadUrl: 'https://example.invalid/s1_zh.srt',
                ),
                const TrackNode(
                  type: 'text',
                  title: '02 添い寝.srt',
                  hash: '9/s2_zh',
                  mediaDownloadUrl: 'https://example.invalid/s2_zh.srt',
                ),
              ],
            ),
            TrackNode(
              type: 'folder',
              title: '日文',
              children: [
                const TrackNode(
                  type: 'text',
                  title: '01 耳かき.srt',
                  hash: '9/s1_ja',
                  mediaDownloadUrl: 'https://example.invalid/s1_ja.srt',
                ),
              ],
            ),
          ],
        ),
      ];

      final api = _StubSubtitleApi(
        tracksByWork: {9: tracks},
        subtitleHandler: (node) async => switch (node.hash) {
          '9/s1_zh' => '[00:01.00]中文第一章',
          '9/s1_ja' => '[00:01.00]日本語第一章',
          '9/s2_zh' => '[00:01.00]中文第二章',
          _ => '[00:01.00]Other',
        },
      );

      final notes = ListeningNotes(
        library,
        player,
        settings: settings,
        api: api,
        checkNetwork: () async => [ConnectivityResult.wifi],
      );

      final flat = tracks.expand((n) => n.flatten()).toList();
      await player.playWork(Work.fromJson({'id': 9, 'title': 'Multi'}), flat);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(notes.cues.single.text, '中文第一章');
      expect(notes.subtitleSource, SubtitleSource.auto);

      // Switch app language to Japanese -> auto-match re-evaluates to Japanese version.
      settings.locale = const Locale('ja', 'JP');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(notes.cues.single.text, '日本語第一章');
      expect(notes.subtitleSource, SubtitleSource.auto);

      // Manually override chapter 1 with local subtitle; chapter 2 remains auto-matched.
      await notes.importSubtitle('custom.lrc', '[00:01.00]手动字幕');
      expect(notes.subtitleSource, SubtitleSource.manual);
      expect(notes.cues.single.text, '手动字幕');

      await player.seekToIndex(1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(notes.subtitleSource, SubtitleSource.auto);
      expect(notes.cues.single.text, '中文第二章');

      // Back to chapter 1 -> manual override is still preserved.
      await player.seekToIndex(0);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(notes.subtitleSource, SubtitleSource.manual);
      expect(notes.cues.single.text, '手动字幕');

      // Restore auto-match -> deletes manual override and reloads Japanese auto-matched subtitle.
      await notes.restoreAutoSubtitle();
      expect(notes.subtitleSource, SubtitleSource.auto);
      expect(notes.cues.single.text, '日本語第一章');

      notes.dispose();
      library.dispose();
      player.dispose();
      settings.dispose();
    },
  );
}
