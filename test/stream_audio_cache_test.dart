import 'dart:io';
import 'dart:typed_data';

import 'package:asmr_one/core/models/track.dart';
import 'package:asmr_one/core/models/work.dart';
import 'package:asmr_one/core/storage/app_prefs.dart';
import 'package:asmr_one/core/storage/stream_audio_cache.dart';
import 'package:asmr_one/state/player_state.dart';
import 'package:asmr_one/state/settings_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'player_state_test.dart' show TestAudio, TestLibrary;

/// 支持 Range 请求并记录传输字节数的本地模拟音频服务器。
class _MockAudioServer {
  _MockAudioServer(this.payload);

  final Uint8List payload;
  late HttpServer _server;
  int requestCount = 0;
  int bytesServed = 0;

  Uri get uri => Uri.parse('http://127.0.0.1:${_server.port}/track.mp3');

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen((req) async {
      requestCount++;
      final range = req.headers.value(HttpHeaders.rangeHeader);
      req.response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      req.response.headers.set(HttpHeaders.contentTypeHeader, 'audio/mpeg');
      if (range != null && range.startsWith('bytes=')) {
        final parts = range.substring('bytes='.length).split('-');
        final start = int.parse(parts[0]);
        final end = parts.length > 1 && parts[1].isNotEmpty
            ? int.parse(parts[1])
            : payload.length - 1;
        final slice = payload.sublist(start, end + 1);
        req.response.statusCode = HttpStatus.partialContent;
        req.response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/${payload.length}',
        );
        req.response.contentLength = slice.length;
        bytesServed += slice.length;
        req.response.add(slice);
        await req.response.close();
        return;
      }
      req.response.statusCode = HttpStatus.ok;
      req.response.contentLength = payload.length;
      bytesServed += payload.length;
      req.response.add(payload);
      await req.response.close();
    });
  }

  void resetCounts() {
    requestCount = 0;
    bytesServed = 0;
  }

  Future<void> close() => _server.close(force: true);
}

Future<Uint8List> _readAll(Uri uri, {String? range}) async {
  if (uri.scheme == 'file') {
    return File(uri.toFilePath()).readAsBytes();
  }
  final client = HttpClient();
  try {
    final req = await client.getUrl(uri);
    if (range != null) req.headers.set(HttpHeaders.rangeHeader, range);
    final res = await req.close();
    final chunks = <int>[];
    await for (final c in res) {
      chunks.addAll(c);
    }
    return Uint8List.fromList(chunks);
  } finally {
    client.close(force: true);
  }
}

class _DownloadableLibrary extends TestLibrary {
  final Map<String, String> localPaths = {};

  @override
  Future<Map<String, String>> downloadedPaths(int workId) async => localPaths;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    // Allow loopback HttpClient requests to the local mock server in tests.
    HttpOverrides.global = null;
  });

  test(
    'controlled replay experiment: cache off transfers 2x payload while cache on transfers 0 upstream bytes on replay',
    () async {
      final payload = Uint8List.fromList(
        List.generate(256 * 1024, (i) => (i * 31) & 0xff),
      );
      final server = _MockAudioServer(payload);
      await server.start();
      addTearDown(server.close);

      final dir = await Directory.systemTemp.createTemp('asmr-stream-exp-');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      final cache = StreamAudioCache(directoryProvider: () async => dir);
      addTearDown(cache.dispose);
      const key = AudioCacheKey(
        accountScope: 'guest',
        workId: 100,
        trackId: '100/0',
        lowQuality: false,
      );

      // Baseline (cache OFF): play twice directly from upstream.
      server.resetCounts();
      final offPlay1 = await _readAll(server.uri);
      final offFirstBytes = server.bytesServed;
      final offPlay2 = await _readAll(server.uri);
      final offReplayBytes = server.bytesServed - offFirstBytes;
      expect(offPlay1, payload);
      expect(offPlay2, payload);
      expect(offFirstBytes, payload.length);
      expect(offReplayBytes, payload.length);

      // Experiment (cache ON): clear cache, then play twice through cache.
      await cache.clearAll(includeActive: true);
      server.resetCounts();
      cache.resetMetrics();

      final firstUri = await cache.resolvePlayableUri(
        key: key,
        remoteUri: server.uri,
      );
      expect(firstUri, isNotNull);
      expect(firstUri!.scheme, 'http'); // proxy stream-and-cache on miss
      final onPlay1 = await _readAll(firstUri);
      final onFirstBytes = server.bytesServed;
      expect(onPlay1, payload);
      expect(onFirstBytes, payload.length);
      expect(await cache.refreshStats(), payload.length);

      // Replay: hits local complete file -> 0 upstream bytes!
      final secondUri = await cache.resolvePlayableUri(
        key: key,
        remoteUri: server.uri,
      );
      expect(secondUri, isNotNull);
      expect(secondUri!.scheme, 'file');
      final onPlay2 = await _readAll(secondUri);
      final onReplayBytes = server.bytesServed - onFirstBytes;
      expect(onPlay2, payload);
      expect(onReplayBytes, 0);
      expect(cache.cacheHitBytes, payload.length);
    },
  );

  test(
    'seeking into an uncached Range passes through 206 without marking partial data complete',
    () async {
      final payload = Uint8List.fromList(
        List.generate(64 * 1024, (i) => i & 0xff),
      );
      final server = _MockAudioServer(payload);
      await server.start();
      addTearDown(server.close);

      final dir = await Directory.systemTemp.createTemp('asmr-stream-seek-');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      final cache = StreamAudioCache(directoryProvider: () async => dir);
      addTearDown(cache.dispose);
      const key = AudioCacheKey(
        accountScope: 'uid:u1',
        workId: 200,
        trackId: '200/0',
        lowQuality: false,
      );

      final proxyUri = await cache.resolvePlayableUri(
        key: key,
        remoteUri: server.uri,
      );
      expect(proxyUri, isNotNull);

      // Seek to middle of uncached track.
      final midSlice = await _readAll(proxyUri!, range: 'bytes=32768-40959');
      expect(midSlice, payload.sublist(32768, 40960));
      expect(await cache.lookupComplete(key), isNull);
    },
  );

  test(
    'cache isolates account scope and quality, survives token refresh, and evicts oldest idle LRU entry first',
    () async {
      final payload = Uint8List.fromList(List.filled(60 * 1024, 7));
      final server = _MockAudioServer(payload);
      await server.start();
      addTearDown(server.close);

      final dir = await Directory.systemTemp.createTemp('asmr-stream-lru-');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });

      var clock = DateTime(2026, 1, 1, 10, 0);
      final cache = StreamAudioCache(
        directoryProvider: () async => dir,
        maxBytes: 100 * 1024, // 100 KB limit; two 60 KB files exceed it.
        now: () => clock,
      );
      addTearDown(cache.dispose);

      // Account scope invariance across token refreshes.
      final scopeBeforeRefresh = StreamAudioCache.accountScopeFor(
        hasToken: true,
        userId: 'user-42',
        userName: 'alice',
      );
      final scopeAfterRefresh = StreamAudioCache.accountScopeFor(
        hasToken: true,
        userId: 'user-42',
        userName: 'alice',
      );
      final guestScope = StreamAudioCache.accountScopeFor(hasToken: false);
      expect(scopeBeforeRefresh, scopeAfterRefresh);
      expect(scopeBeforeRefresh, isNot(guestScope));

      final highKey = AudioCacheKey(
        accountScope: scopeBeforeRefresh,
        workId: 1,
        trackId: '1/0',
        lowQuality: false,
      );
      final lowKey = AudioCacheKey(
        accountScope: scopeBeforeRefresh,
        workId: 1,
        trackId: '1/0',
        lowQuality: true,
      );
      final guestKey = AudioCacheKey(
        accountScope: guestScope,
        workId: 1,
        trackId: '1/0',
        lowQuality: false,
      );

      // Populate highKey (60 KB) at t=0.
      final uri1 = await cache.resolvePlayableUri(
        key: highKey,
        remoteUri: server.uri,
      );
      await _readAll(uri1!);
      expect(await cache.lookupComplete(highKey), isNotNull);
      // Low quality & guest must NOT hit highKey.
      expect(await cache.lookupComplete(lowKey), isNull);
      expect(await cache.lookupComplete(guestKey), isNull);

      // Populate lowKey (60 KB) at t=10m -> total 120 KB > 100 KB -> highKey (older) evicted, lowKey (newer) kept!
      clock = clock.add(const Duration(minutes: 10));
      final uri2 = await cache.resolvePlayableUri(
        key: lowKey,
        remoteUri: server.uri,
      );
      await _readAll(uri2!);
      expect(await cache.lookupComplete(highKey), isNull);
      expect(await cache.lookupComplete(lowKey), isNotNull);
      expect(cache.cachedBytes, 60 * 1024);

      // Mark lowKey active, then add guestKey (60 KB) at t=20m:
      // lowKey is active so it must be skipped during eviction until released!
      cache.markActive(lowKey.id);
      clock = clock.add(const Duration(minutes: 10));
      final uri3 = await cache.resolvePlayableUri(
        key: guestKey,
        remoteUri: server.uri,
      );
      await _readAll(uri3!);
      expect(await cache.lookupComplete(lowKey), isNotNull);
      expect(await cache.lookupComplete(guestKey), isNotNull);

      // Release lowKey -> deferred LRU eviction drops older lowKey and retains newer guestKey.
      cache.releaseActive(lowKey.id);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await cache.lookupComplete(lowKey), isNull);
      expect(await cache.lookupComplete(guestKey), isNotNull);
      expect(cache.cachedBytes, 60 * 1024);
    },
  );

  test(
    'PlayerState prioritizes downloaded files over cache, falls back on cache failure, and clearing cache keeps downloads playable offline',
    () async {
      SharedPreferences.setMockInitialValues({
        'player.streamCache': true,
        'player.lowQuality': false,
      });
      final prefs = await AppPrefs.load();
      final settings = SettingsState(prefs);
      final dlDir = await Directory.systemTemp.createTemp('asmr-dl-');
      final cacheDir = await Directory.systemTemp.createTemp('asmr-cache-');
      addTearDown(() async {
        if (await dlDir.exists()) await dlDir.delete(recursive: true);
        if (await cacheDir.exists()) await cacheDir.delete(recursive: true);
      });

      final downloadedFile = await File(
        p.join(dlDir.path, '01.mp3'),
      ).writeAsBytes(List.filled(1024, 1));
      final library = _DownloadableLibrary()
        ..localPaths['50/0'] = downloadedFile.path;
      final cache = StreamAudioCache(directoryProvider: () async => cacheDir);
      addTearDown(cache.dispose);
      final audio = TestAudio();
      final player = PlayerState(
        settings: settings,
        library: library,
        audioPlayer: audio,
        audioCache: cache,
        accountScope: () => 'guest',
      );
      addTearDown(player.dispose);
      addTearDown(settings.dispose);

      final work = Work.fromJson({'id': 50, 'title': 'Mixed Work'});
      final downloadedTrack = TrackNode.fromJson({
        'type': 'audio',
        'hash': '50/0',
        'title': '01.mp3',
        'mediaStreamUrl': 'https://cdn.example/50_0.mp3',
      }).flatten().single;
      final onlineTrack = TrackNode.fromJson({
        'type': 'audio',
        'hash': '50/1',
        'title': '02.mp3',
        'mediaStreamUrl': 'https://cdn.example/50_1.mp3',
      }).flatten().single;

      await player.playWork(work, [downloadedTrack, onlineTrack]);
      final sources = audio.sources.cast<ja.UriAudioSource>();
      // Track 0 uses downloaded file directly (no stream cache occupied).
      expect(sources[0].uri.scheme, 'file');
      expect(sources[0].uri.toFilePath(), downloadedFile.path);
      // Track 1 uses local stream cache proxy.
      expect(sources[1].uri.host, '127.0.0.1');

      // Clearing temporary stream cache never deletes downloaded files.
      await player.stop();
      await cache.clearAll();
      expect(await downloadedFile.exists(), isTrue);
      expect(
        await player.playLocalFiles(work, {'50/0': downloadedFile.path}),
        isTrue,
      );

      // Broken cache directory gracefully falls back to direct remote streaming.
      final brokenCache = StreamAudioCache(
        directoryProvider: () => Future.error(const FileSystemException('full')),
      );
      addTearDown(brokenCache.dispose);
      final fallbackAudio = TestAudio();
      final fallbackPlayer = PlayerState(
        settings: settings,
        library: TestLibrary(),
        audioPlayer: fallbackAudio,
        audioCache: brokenCache,
        accountScope: () => 'guest',
      );
      addTearDown(fallbackPlayer.dispose);

      await fallbackPlayer.playSingle(work, onlineTrack);
      final fallbackUri =
          (fallbackAudio.sources.single as ja.UriAudioSource).uri;
      expect(fallbackUri.toString(), 'https://cdn.example/50_1.mp3');
    },
  );
}
