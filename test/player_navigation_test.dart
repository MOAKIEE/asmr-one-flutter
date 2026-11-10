import 'package:asmr_one/core/models/work.dart';
import 'package:asmr_one/core/storage/app_prefs.dart';
import 'package:asmr_one/state/player_state.dart' as app;
import 'package:asmr_one/state/settings_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_state_test.dart' show TestAudio, TestLibrary;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SettingsState settings;
  late TestAudio audio;
  late app.PlayerState player;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'ui.useCoverAccent': false});
    settings = SettingsState(await AppPrefs.load());
    audio = TestAudio()..shuffledOrder = [0, 2, 1];
    player = app.PlayerState(
      settings: settings,
      library: TestLibrary(),
      audioPlayer: audio,
    );
  });
  tearDown(() {
    player.dispose();
    settings.dispose();
  });

  Future<void> load() => player.playLocalFiles(Work.fromJson({'id': 1}), {
    'a': '/a.mp3',
    'b': '/b.mp3',
    'c': '/c.mp3',
  });

  test('manual next and previous follow shuffle order including the original last index', () async {
    await load();
    await player.toggleShuffle();
    await player.next();
    expect(player.currentIndex, 2);
    expect(player.hasNext, isTrue);
    await player.next();
    expect(player.currentIndex, 1);
    expect(player.hasNext, isFalse);
    await player.previous();
    expect(player.currentIndex, 2);
  });

  test('shuffled completion pauses and resets even when final track is not the original last', () async {
    await load();
    await player.toggleShuffle();
    await player.seekToIndex(1);
    audio.events.add(PlayerState(true, ProcessingState.completed));
    await Future<void>.delayed(Duration.zero);
    expect(player.playing, isFalse);
    expect(player.currentIndex, 0);
    expect(audio.position, Duration.zero);
  });

  test('manual navigation wraps in queue loop mode and skips in single-track loop mode', () async {
    await load();
    await player.toggleShuffle();
    await player.cycleLoopMode();
    await player.seekToIndex(1);
    expect(player.hasNext, isTrue);
    await player.next();
    expect(player.currentIndex, 0);
    await player.previous();
    expect(player.currentIndex, 1);
    await player.cycleLoopMode();
    await player.seekToIndex(0);
    await player.next();
    expect(player.currentIndex, 2);
  });

  test(
    'shuffle visits each logical track once with automatic next disabled',
    () async {
      settings.autoPlayNext = false;
      await load();
      await player.toggleShuffle();
      final visited = <int>{player.currentIndex};
      while (player.hasNext) {
        await player.next();
        expect(visited.add(player.currentIndex), isTrue);
        expect(audio.sources, hasLength(1));
      }
      expect(visited, {0, 1, 2});
      await player.cycleLoopMode();
      await player.next();
      expect(player.currentIndex, 0);
    },
  );
}
