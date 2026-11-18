import 'dart:async';
import 'dart:io';

import 'package:asmr_one/core/api/api_client.dart';
import 'package:asmr_one/core/models/track.dart';
import 'package:asmr_one/core/models/work.dart';
import 'package:asmr_one/core/storage/app_prefs.dart';
import 'package:asmr_one/core/storage/library_db.dart';
import 'package:asmr_one/state/library_state.dart';
import 'package:asmr_one/state/player_state.dart' as app;
import 'package:asmr_one/state/settings_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestLibrary implements LibraryState {
  int saved = 12000;
  @override
  Future<Map<String, String>> downloadedPaths(int workId) async => {};
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
  final indices = StreamController<int?>.broadcast();
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
  Stream<int?> get currentIndexStream => indices.stream;
  @override
  Stream<Duration?> get durationStream => Stream.value(duration);
  List<int>? shuffledOrder;
  @override
  List<int> get effectiveIndices => shuffleModeEnabled && shuffledOrder != null
      ? shuffledOrder!
      : List.generate(sources.length, (index) => index);
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
    indices.add(index);
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
    if (index != null) indices.add(index);
  }

  @override
  Future<void> dispose() async {
    await events.close();
    await positions.close();
    await indices.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'legacy session restores playback and migrates to separate documents without autoplay',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsState(await AppPrefs.load());
      final dir = await Directory.systemTemp.createTemp('asmr-session-');
      final file = await File('${dir.path}/track.mp3').writeAsString('audio');
      final session = <String, Object?>{};
      final audio = TestAudio();
      final player = app.PlayerState(
        settings: settings,
        library: TestLibrary(),
        audioPlayer: audio,
        writeSession: (documents) async => session.addAll(documents),
      );
      await player.playLocalFiles(Work.fromJson({'id': 3, 'title': 'Saved'}), {
        'a': file.path,
      });
      audio.position = const Duration(seconds: 23);
      await player.pause();
      player.dispose();
      final legacy = <String, Object?>{
        'playerSession': {
          ...session['playerSession'] as Map,
          'items': session['playerQueue'],
        },
      };
      final restoredAudio = TestAudio();
      final restored = app.PlayerState(
        settings: settings,
        library: TestLibrary(),
        audioPlayer: restoredAudio,
        readSession: (_) async => legacy,
        writeSession: (documents) async => legacy.addAll(documents),
      );
      await restored.restoreSession();
      expect(restored.currentItem!.workId, 3);
      expect(restoredAudio.position, const Duration(seconds: 23));
      expect(restoredAudio.playCalls, 0);
      expect(legacy['playerQueue'], hasLength(1));
      expect(legacy['playerSession'], {
        'index': 0,
        'position': 23000,
        'shuffle': false,
        'loop': 0,
      });
      restored.dispose();
      settings.dispose();
      await dir.delete(recursive: true);
    },
  );
  testWidgets('periodic saves write only the playback cursor', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsState(await AppPrefs.load());
    final audio = TestAudio();
    final writes = <Map<String, Object?>>[];
    final player = app.PlayerState(
      settings: settings,
      library: TestLibrary(),
      audioPlayer: audio,
      writeSession: (documents) async => writes.add(documents),
    );
    await player.playLocalFiles(Work.fromJson({'id': 3, 'title': 'Saved'}), {
      'a': '/a.mp3',
      'b': '/b.mp3',
    });
    expect(writes.last['playerQueue'], hasLength(2));
    expect(writes.last['playerSession'], isNot(contains('items')));
    writes.clear();

    audio.position = const Duration(seconds: 23);
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();

    expect(writes, [
      {
        'playerSession': {
          'index': 0,
          'position': 23000,
          'shuffle': false,
          'loop': 0,
        },
      },
    ]);

    await player.stop();
    expect(writes.last, {'playerSession': null, 'playerQueue': null});
    player.dispose();
    settings.dispose();
  });
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

  test(
    'media item ids exclude auth tokens, disambiguate missing hashes, and support background track skipping',
    () async {
      const fakeToken = 'secret-token-for-test';
      SharedPreferences.setMockInitialValues({'auth.token': fakeToken});
      final prefs = await AppPrefs.load();
      final settings = SettingsState(prefs);
      final api = ApiClient()..attachPrefs(prefs);
      final audio = TestAudio();
      final library = TestLibrary()..saved = 0;
      final player = app.PlayerState(
        settings: settings,
        library: library,
        audioPlayer: audio,
        api: api,
      );

      final work = Work.fromJson({'id': 10, 'title': 'Paid work'});
      final tracks = [
        // 付费回退曲目：无 mediaStreamUrl，靠 mediaStreamUrl(hash) 带上 token
        TrackNode.fromJson({
          'type': 'audio',
          'title': '01_intro.mp3',
          'hash': '10/0',
        }).flatten().single,
        TrackNode.fromJson({
          'type': 'audio',
          'title': '02_main.mp3',
          'hash': '10/1',
        }).flatten().single,
        // 无 hash 曲目（带查询参数地址），验证队列内唯一标识不泄露 URL
        TrackNode.fromJson({
          'type': 'audio',
          'title': '03_bonus.mp3',
          'mediaStreamUrl': 'https://cdn.example.invalid/bonus.mp3?token=$fakeToken',
        }).flatten().single,
        TrackNode.fromJson({
          'type': 'audio',
          'title': '04_outro.mp3',
          'mediaStreamUrl': 'https://cdn.example.invalid/outro.mp3?token=$fakeToken',
        }).flatten().single,
      ];

      final res = await player.playWork(work, tracks);
      expect(res.queued, 4);
      expect(res.unplayable, 0);

      final mediaItems = audio.sources
          .cast<UriAudioSource>()
          .map((s) => s.tag as MediaItem)
          .toList();
      final uris = audio.sources
          .cast<UriAudioSource>()
          .map((s) => s.uri.toString())
          .toList();

      // 音频数据源仍保留凭据 URI
      expect(uris[0], contains('token=$fakeToken'));
      expect(uris[1], contains('token=$fakeToken'));

      // 当前与全部队列 MediaItem.id 均不含令牌且彼此唯一
      for (final item in mediaItems) {
        expect(item.id, isNot(contains(fakeToken)));
        expect(item.id, isNot(contains('http')));
      }
      expect(mediaItems.map((e) => e.id).toSet(), hasLength(4));
      expect(mediaItems[0].id, 'work:10:hash:10/0');
      expect(mediaItems[1].id, 'work:10:hash:10/1');
      expect(mediaItems[2].id, 'work:10:track:2');
      expect(mediaItems[3].id, 'work:10:track:3');

      // 当前媒体项也不含令牌，且模拟后台切歌正常
      expect(mediaItems[audio.index!].id, 'work:10:hash:10/0');
      await player.next();
      await Future<void>.delayed(Duration.zero);
      expect(player.currentIndex, 1);
      expect(player.currentItem?.hash, '10/1');
      expect(mediaItems[audio.index!].id, 'work:10:hash:10/1');

      await player.previous();
      await Future<void>.delayed(Duration.zero);
      expect(player.currentIndex, 0);
      expect(mediaItems[audio.index!].id, 'work:10:hash:10/0');

      // 单曲模式下无 hash 曲目仍保留其在原队列中的唯一索引标识
      settings.autoPlayNext = false;
      await Future<void>.delayed(Duration.zero);
      await player.seekToIndex(3);
      await Future<void>.delayed(Duration.zero);
      expect(audio.sources, hasLength(1));
      final singleItem = (audio.sources.single as UriAudioSource).tag as MediaItem;
      expect(singleItem.id, 'work:10:track:3');
      expect(singleItem.id, isNot(contains(fakeToken)));

      player.dispose();
      settings.dispose();
    },
  );

  test(
    'removing a track while paused persists the updated queue across restart',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsState(await AppPrefs.load());
      final dir = await Directory.systemTemp.createTemp('asmr-remove-paused-');
      final fileA = await File('${dir.path}/a.mp3').writeAsString('a');
      final fileB = await File('${dir.path}/b.mp3').writeAsString('b');
      final fileC = await File('${dir.path}/c.mp3').writeAsString('c');
      final session = <String, Object?>{};
      final audio = TestAudio();
      final library = TestLibrary()..saved = 0;
      final player = app.PlayerState(
        settings: settings,
        library: library,
        audioPlayer: audio,
        writeSession: (documents) async => session.addAll(documents),
      );

      await player.playLocalFiles(
        Work.fromJson({'id': 7, 'title': 'Three tracks'}),
        {'a': fileA.path, 'b': fileB.path, 'c': fileC.path},
        metadata: [
          DownloadRow(workId: 7, hash: 'a', title: 'Track 1', filePath: fileA.path, trackIndex: 0),
          DownloadRow(workId: 7, hash: 'b', title: 'Track 2', filePath: fileB.path, trackIndex: 1),
          DownloadRow(workId: 7, hash: 'c', title: 'Track 3', filePath: fileC.path, trackIndex: 2),
        ],
      );
      await player.seekToIndex(1);
      await Future<void>.delayed(Duration.zero);
      audio.position = const Duration(seconds: 23);
      await player.pause();
      expect(player.playing, isFalse);

      // 暂停状态下移除第一首曲目后直接结束进程
      await player.removeFromQueue(0);
      expect(player.queue.map((e) => e.title), ['Track 2', 'Track 3']);
      expect(player.currentIndex, 0);
      player.dispose();

      // 重建播放器并恢复会话
      final restoredAudio = TestAudio();
      final restored = app.PlayerState(
        settings: settings,
        library: library,
        audioPlayer: restoredAudio,
        readSession: (_) async => session,
      );
      await restored.restoreSession();

      expect(restored.queue.map((e) => e.title), ['Track 2', 'Track 3']);
      expect(restored.currentIndex, 0);
      expect(restored.currentItem?.hash, 'b');
      expect(restoredAudio.position, const Duration(seconds: 23));
      expect(restoredAudio.playCalls, 0);

      restored.dispose();
      settings.dispose();
      await dir.delete(recursive: true);
    },
  );

  test(
    'playWork computes start index correctly when earlier tracks are unplayable',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await AppPrefs.load();
      final settings = SettingsState(prefs);
      final api = ApiClient()..attachPrefs(prefs);
      final audio = TestAudio();
      final library = TestLibrary()..saved = 0;
      final player = app.PlayerState(
        settings: settings,
        library: library,
        audioPlayer: audio,
        api: api,
      );

      final tracks = [
        // 无 hash 且无直链 -> 不可播放
        TrackNode.fromJson({'type': 'audio', 'title': 'unplayable.mp3'}).flatten().single,
        TrackNode.fromJson({
          'type': 'audio',
          'title': 'track_a.mp3',
          'mediaStreamUrl': 'https://cdn.example.invalid/a.mp3',
        }).flatten().single,
        TrackNode.fromJson({
          'type': 'audio',
          'title': 'track_b.mp3',
          'mediaStreamUrl': 'https://cdn.example.invalid/b.mp3',
        }).flatten().single,
      ];

      final result = await player.playWork(
        Work.fromJson({'id': 9, 'title': 'Filtered start'}),
        tracks,
        startIndex: 2,
      );

      expect(result.queued, 2);
      expect(result.unplayable, 1);
      expect(player.currentIndex, 1);
      expect(player.currentItem?.title, 'track_b.mp3');

      player.dispose();
      settings.dispose();
    },
  );
}
