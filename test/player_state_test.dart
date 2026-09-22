import 'dart:async';

import 'package:asmr_one/core/models/work.dart';
import 'package:asmr_one/core/storage/app_prefs.dart';
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
  final events = StreamController<PlayerState>.broadcast();
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
    this.sources = sources;
    index = initialIndex;
    position = initialPosition ?? Duration.zero;
    return duration;
  }

  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> setShuffleModeEnabled(bool enabled) async {}
  @override
  Future<void> setLoopMode(LoopMode mode) async {
    loopMode = mode;
  }

  @override
  Future<void> play() async {
    playing = true;
  }

  @override
  Future<void> pause() async {
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
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
