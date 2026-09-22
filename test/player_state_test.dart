import 'dart:async';
import 'dart:io';

import 'package:asmr_one/core/models/work.dart';
import 'package:asmr_one/core/storage/app_prefs.dart';
import 'package:asmr_one/core/storage/library_db.dart';
import 'package:asmr_one/state/library_state.dart';
import 'package:asmr_one/state/player_state.dart' as app;
import 'package:asmr_one/state/settings_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestLibrary implements LibraryState {
  int saved = 12000;
  @override
  Future<int> progressFor(String hash) async => saved;
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
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestAudio implements AudioPlayer {
  bool failLoading = false;
  int playCalls = 0;
  final events = StreamController<PlayerState>.broadcast();
  final positions = StreamController<Duration>.broadcast();
  @override
  bool shuffleModeEnabled = false;
  @override
  double volume = 1;
  @override
  double speed = 1;
  @override
  Future<void> setVolume(double value) async {
    volume = value;
  }

  List<AudioSource> sources = [];
  int? index;
  @override
  Duration position = Duration.zero;
  @override
  Duration? duration = const Duration(minutes: 1);
  @override
  bool playing = false;
  @override
  LoopMode loopMode = LoopMode.off;
  @override
  Stream<int?> get currentIndexStream => const Stream.empty();
  @override
  Stream<Duration> get positionStream => positions.stream;
  @override
  Stream<PlayerException> get errorStream => const Stream.empty();
  @override
  Stream<PlayerState> get playerStateStream => events.stream;
  @override
  Future<Duration?> setAudioSources(
    List<AudioSource> sources, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
    ShuffleOrder? shuffleOrder,
  }) async {
    if (failLoading) throw StateError('missing audio');
    this.sources = sources;
    index = initialIndex;
    position = initialPosition ?? Duration.zero;
    return duration;
  }

  @override
  Future<void> setSpeed(double speed) async {
    this.speed = speed;
  }

  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {
    shuffleModeEnabled = enabled;
  }

  @override
  Future<void> shuffle() async {}
  @override
  Future<void> setLoopMode(LoopMode mode) async {
    loopMode = mode;
  }

  @override
  Future<void> play() async {
    playCalls++;
    playing = true;
  }

  @override
  Future<void> pause() async {
    playing = false;
  }

  @override
  Future<void> stop() async {
    playing = false;
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    this.position = position ?? Duration.zero;
    this.index = index ?? this.index;
  }

  @override
  Future<void> dispose() async {
    await events.close();
    await positions.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'session restores the selected track and position without autoplay',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsState(await AppPrefs.load());
      final dir = await Directory.systemTemp.createTemp('asmr-session-');
      final file = await File('${dir.path}/track.mp3').writeAsString('audio');
      Object? session;
      final audio = TestAudio();
      final player = app.PlayerState(
        settings: settings,
        library: TestLibrary(),
        audioPlayer: audio,
        writeSession: (value) async {
          session = value;
        },
      );
      await player.playLocalFiles(Work.fromJson({'id': 3, 'title': 'Saved'}), {
        'a': file.path,
      });
      audio.position = const Duration(seconds: 23);
      await player.pause();
      player.dispose();
      final restoredAudio = TestAudio();
      final restored = app.PlayerState(
        settings: settings,
        library: TestLibrary(),
        audioPlayer: restoredAudio,
        readSession: () async => session,
      );
      await restored.restoreSession();
      expect(restored.currentItem!.workId, 3);
      expect(restoredAudio.position, const Duration(seconds: 23));
      expect(restoredAudio.playCalls, 0);
      restored.dispose();
      settings.dispose();
      await dir.delete(recursive: true);
    },
  );
  test('A-B loop seeks at B and rejects invalid end points', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsState(await AppPrefs.load());
    final audio = TestAudio()..playing = true;
    final player = app.PlayerState(
      settings: settings,
      library: TestLibrary(),
      audioPlayer: audio,
    );
    audio.position = const Duration(seconds: 4);
    player.markLoopStart();
    expect(player.markLoopEnd(), isFalse);
    audio.position = const Duration(seconds: 8);
    expect(player.markLoopEnd(), isTrue);
    audio.positions.add(const Duration(seconds: 9));
    await Future<void>.delayed(Duration.zero);
    expect(audio.position, const Duration(seconds: 4));
    player.clearAbLoop();
    expect(player.loopEnd, isNull);
    player.dispose();
    settings.dispose();
  });
  testWidgets(
    'sleep timer fades during final 30 seconds and restores volume after pause',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsState(await AppPrefs.load());
      final audio = TestAudio()..playing = true;
      var now = DateTime(2026);
      final player = app.PlayerState(
        settings: settings,
        library: TestLibrary(),
        audioPlayer: audio,
        now: () => now,
      );
      player.setSleepTimer(1);
      now = now.add(const Duration(seconds: 45));
      await tester.pump(const Duration(seconds: 1));
      expect(audio.volume, closeTo(0.5, 0.01));
      now = now.add(const Duration(seconds: 15));
      await tester.pump(const Duration(seconds: 1));
      expect(audio.playing, isFalse);
      expect(player.sleepDeadline, isNull);
      expect(audio.volume, 1);
      player.dispose();
      settings.dispose();
    },
  );
  test(
    'failed source loading does not report success or start playback',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsState(await AppPrefs.load());
      final audio = TestAudio()..failLoading = true;
      final player = app.PlayerState(
        settings: settings,
        library: TestLibrary(),
        audioPlayer: audio,
      );
      expect(
        await player.playLocalFiles(Work.fromJson({'id': 1}), {
          'a': '/missing.mp3',
        }),
        isFalse,
      );
      expect(audio.playCalls, 0);
      expect(player.error, contains('missing audio'));
      player.dispose();
      settings.dispose();
    },
  );
  test(
    'offline queue uses original titles and track order instead of hashes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsState(await AppPrefs.load());
      final player = app.PlayerState(
        settings: settings,
        library: TestLibrary(),
        audioPlayer: TestAudio(),
      );
      await player.playLocalFiles(
        Work.fromJson({'id': 1}),
        {'a': '/a_last.mp3', 'z': '/z_first.mp3'},
        metadata: [
          DownloadRow(
            workId: 1,
            hash: 'a',
            title: 'Last',
            filePath: '/a_last.mp3',
            trackIndex: 1,
          ),
          DownloadRow(
            workId: 1,
            hash: 'z',
            title: 'First',
            filePath: '/z_first.mp3',
            trackIndex: 0,
          ),
        ],
      );
      expect(player.queue.map((e) => e.title), ['First', 'Last']);
      player.dispose();
      settings.dispose();
    },
  );
  test('local playback restores progress, respects single-track mode and manual next', () async {
    SharedPreferences.setMockInitialValues({
      'player.autoPlayNext': false,
      'ui.useCoverAccent': false,
    });
    final settings = SettingsState(await AppPrefs.load());
    final audio = TestAudio();
    final library = TestLibrary();
    final player = app.PlayerState(
      settings: settings,
      library: library,
      audioPlayer: audio,
    );
    await player.playLocalFiles(Work.fromJson({'id': 1, 'title': 'work'}), {
      'a': '/a.mp3',
      'b': '/b.mp3',
    });
    expect(audio.position, const Duration(seconds: 12));
    expect(audio.sources, hasLength(1));
    expect(player.queue, hasLength(2));
    audio.events.add(PlayerState(true, ProcessingState.completed));
    await Future<void>.delayed(Duration.zero);
    expect(audio.playing, isFalse);
    await player.next();
    expect(player.currentIndex, 1);
    expect(audio.index, 0);
    expect(audio.position, Duration.zero);
    settings.autoPlayNext = true;
    await Future<void>.delayed(Duration.zero);
    expect(audio.sources, hasLength(2));
    expect(audio.index, 1);
    expect(audio.playing, isTrue);
    library.saved = 59000;
    await player.playLocalFiles(Work.fromJson({'id': 1}), {'a': '/a.mp3'});
    expect(audio.position, Duration.zero);
    player.dispose();
    settings.dispose();
  });
}
