import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:asmr_one/core/api/api_client.dart';
import 'package:asmr_one/core/models/track.dart';
import 'package:asmr_one/core/models/work.dart';
import 'package:asmr_one/core/storage/app_prefs.dart';
import 'package:asmr_one/core/storage/stream_audio_cache.dart';
import 'package:asmr_one/state/auth_state.dart';
import 'package:asmr_one/state/player_state.dart';
import 'package:asmr_one/state/settings_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client_test.dart' show TestAdapter, jsonResponse;
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
      expect(scopeBeforeRefresh, isNotNull);
      expect(scopeBeforeRefresh, scopeAfterRefresh);
      expect(scopeBeforeRefresh, isNot(guestScope));

      final highKey = AudioCacheKey(
        accountScope: scopeBeforeRefresh!,
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
        accountScope: guestScope!,
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

  test(
    'Android manifest enables cleartext network security config strictly for 127.0.0.1',
    () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      final config = File(
        'android/app/src/main/res/xml/network_security_config.xml',
      ).readAsStringSync();

      expect(
        manifest,
        contains('android:networkSecurityConfig="@xml/network_security_config"'),
      );
      expect(config, contains('cleartextTrafficPermitted="false"'));
      expect(config, contains('cleartextTrafficPermitted="true"'));
      expect(config, contains('<domain includeSubdomains="false">127.0.0.1</domain>'));
    },
  );

  test(
    'cold start skips cache when identity is pending and isolates restored queue per persisted account across token refresh',
    () async {
      final payload = Uint8List.fromList(List.generate(8192, (i) => i & 0xff));
      final server = _MockAudioServer(payload);
      await server.start();
      addTearDown(server.close);

      final dir = await Directory.systemTemp.createTemp('asmr-cold-scope-');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final cache = StreamAudioCache(directoryProvider: () async => dir);
      addTearDown(cache.dispose);

      Map<String, Object?> savedSession() => {
        'playerSession': {
          'index': 0,
          'position': 0,
          'shuffle': false,
          'loop': 0,
        },
        'playerQueue': [
          {
            'workId': 77,
            'workTitle': 'Cold Work',
            'title': '01.mp3',
            'hash': '77/0',
            'url': server.uri.toString(),
            'coverUrl': '',
          },
        ],
      };

      // 1. Legacy token without persisted accountScope -> pending identity -> skips cache (direct remote URL).
      SharedPreferences.setMockInitialValues({
        'auth.token': 'legacy-token',
        'player.streamCache': true,
      });
      final legacyPrefs = await AppPrefs.load();
      final legacySettings = SettingsState(legacyPrefs);
      final legacyAuth = AuthState(legacyPrefs);
      expect(legacyAuth.cacheAccountScope, isNull);
      final legacyAudio = TestAudio();
      final legacyPlayer = PlayerState(
        settings: legacySettings,
        library: TestLibrary(),
        audioPlayer: legacyAudio,
        audioCache: cache,
        accountScope: () => legacyAuth.cacheAccountScope,
        readSession: (_) async => savedSession(),
      );
      await legacyPlayer.restoreSession();
      expect(
        (legacyAudio.sources.single as ja.UriAudioSource).uri,
        server.uri,
      );
      legacyPlayer.dispose();
      legacyAuth.dispose();
      legacySettings.dispose();

      // 2. Account A logs in, caches track 77/0, then cold-starts with refreshed token -> hits Account A's file.
      final api = ApiClient(
        adapter: TestAdapter((request) {
          if (request.method == 'POST' && request.uri.path == '/api/auth/me') {
            final name = (request.data as Map)['name'] as String;
            return jsonResponse({'token': 'tok-$name'});
          }
          final authHeader = request.headers['Authorization'] as String? ?? '';
          if (authHeader.contains('tok-alice')) {
            return jsonResponse({
              'user': {'loggedIn': true, 'id': 'u-alice', 'name': 'alice'},
            });
          }
          return jsonResponse({
            'user': {'loggedIn': true, 'id': 'u-bob', 'name': 'bob'},
          });
        }),
      );

      SharedPreferences.setMockInitialValues({'player.streamCache': true});
      final prefsA = await AppPrefs.load();
      final authA = AuthState(prefsA, api: api);
      expect(await authA.login('alice', 'pass123'), isTrue);
      expect(prefsA.accountScope, 'uid:u-alice');
      final keyA = const AudioCacheKey(
        accountScope: 'uid:u-alice',
        workId: 77,
        trackId: '77/0',
        lowQuality: false,
      );
      final proxyA = await cache.resolvePlayableUri(
        key: keyA,
        remoteUri: server.uri,
      );
      await _readAll(proxyA!);
      authA.dispose();

      // Cold start Account A with a refreshed token (before bootstrap runs): still hits Account A's cache!
      SharedPreferences.setMockInitialValues({
        'auth.token': 'refreshed-tok-alice',
        'auth.accountScope': 'uid:u-alice',
        'player.streamCache': true,
      });
      final coldPrefsA = await AppPrefs.load();
      final coldSettingsA = SettingsState(coldPrefsA);
      final coldAuthA = AuthState(coldPrefsA);
      final coldAudioA = TestAudio();
      final coldPlayerA = PlayerState(
        settings: coldSettingsA,
        library: TestLibrary(),
        audioPlayer: coldAudioA,
        audioCache: cache,
        accountScope: () => coldAuthA.cacheAccountScope,
        readSession: (_) async => savedSession(),
      );
      await coldPlayerA.restoreSession();
      expect(
        (coldAudioA.sources.single as ja.UriAudioSource).uri.scheme,
        'file',
      );
      coldPlayerA.dispose();
      coldAuthA.dispose();
      coldSettingsA.dispose();

      // 3. Cold start Account B -> must NOT hit Account A's file (gets proxy for uid:u-bob).
      SharedPreferences.setMockInitialValues({
        'auth.token': 'tok-bob',
        'auth.accountScope': 'uid:u-bob',
        'player.streamCache': true,
      });
      final coldPrefsB = await AppPrefs.load();
      final coldSettingsB = SettingsState(coldPrefsB);
      final coldAuthB = AuthState(coldPrefsB);
      final coldAudioB = TestAudio();
      final coldPlayerB = PlayerState(
        settings: coldSettingsB,
        library: TestLibrary(),
        audioPlayer: coldAudioB,
        audioCache: cache,
        accountScope: () => coldAuthB.cacheAccountScope,
        readSession: (_) async => savedSession(),
      );
      await coldPlayerB.restoreSession();
      final uriB = (coldAudioB.sources.single as ja.UriAudioSource).uri;
      expect(uriB.scheme, 'http');
      expect(uriB.host, '127.0.0.1');
      coldPlayerB.dispose();
      coldAuthB.dispose();
      coldSettingsB.dispose();
    },
  );

  test(
    '257-track queue keeps first track route alive across jumps and releases old routes when queue is replaced',
    () async {
      final payload = Uint8List.fromList(List.generate(2048, (i) => i & 0xff));
      final server = _MockAudioServer(payload);
      await server.start();
      addTearDown(server.close);

      final dir = await Directory.systemTemp.createTemp('asmr-long-queue-');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final cache = StreamAudioCache(directoryProvider: () async => dir);
      addTearDown(cache.dispose);

      SharedPreferences.setMockInitialValues({
        'player.streamCache': true,
        'player.autoPlayNext': true,
      });
      final settings = SettingsState(await AppPrefs.load());
      final audio = TestAudio();
      final player = PlayerState(
        settings: settings,
        library: TestLibrary(),
        audioPlayer: audio,
        audioCache: cache,
        accountScope: () => 'guest',
      );
      addTearDown(() {
        player.dispose();
        settings.dispose();
      });

      final tracks = [
        for (var i = 0; i < 257; i++)
          TrackNode.fromJson({
            'type': 'audio',
            'hash': '900/$i',
            'title': 'Track $i.mp3',
            'mediaStreamUrl': server.uri.toString(),
          }).flatten().single,
      ];
      await player.playWork(Work.fromJson({'id': 900, 'title': 'Long'}), tracks);
      final sources = audio.sources.cast<ja.UriAudioSource>();
      expect(sources, hasLength(257));
      expect(cache.activeRouteCount, 257);

      final firstUri = sources[0].uri;
      final lastUri = sources[256].uri;
      // Fetch track 0, jump to track 256, return to track 0: all 3 succeed!
      expect(await _readAll(firstUri), payload);
      await player.seekToIndex(256);
      expect(await _readAll(lastUri), payload);
      await player.seekToIndex(0);
      expect(await _readAll(firstUri), payload);

      // Replace queue with a single-track work -> old 257 routes are released and return 404.
      await player.playWork(
        Work.fromJson({'id': 901, 'title': 'Replacement'}),
        [
          TrackNode.fromJson({
            'type': 'audio',
            'hash': '901/0',
            'title': 'Single.mp3',
            'mediaStreamUrl': server.uri.toString(),
          }).flatten().single,
        ],
      );
      expect(cache.activeRouteCount, 1);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final staleReq = await client.getUrl(lastUri);
      final staleRes = await staleReq.close();
      expect(staleRes.statusCode, HttpStatus.notFound);
      await staleRes.drain<void>();
    },
  );

  test(
    'only currently playing track is marked active so finished tracks evict under budget and failed setAudioSources leaks no refs',
    () async {
      final payload = Uint8List.fromList(List.filled(60 * 1024, 3));
      final server = _MockAudioServer(payload);
      await server.start();
      addTearDown(server.close);

      final dir = await Directory.systemTemp.createTemp('asmr-active-scope-');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      var clock = DateTime(2026, 2, 1, 12, 0);
      final cache = StreamAudioCache(
        directoryProvider: () async => dir,
        maxBytes: 100 * 1024, // fits 1 track (60 KB), not 2 (120 KB)
        now: () => clock,
      );
      addTearDown(cache.dispose);

      SharedPreferences.setMockInitialValues({
        'player.streamCache': true,
        'player.autoPlayNext': true,
      });
      final settings = SettingsState(await AppPrefs.load());
      final audio = TestAudio();
      final player = PlayerState(
        settings: settings,
        library: TestLibrary(),
        audioPlayer: audio,
        audioCache: cache,
        accountScope: () => 'guest',
      );
      addTearDown(() {
        player.dispose();
        settings.dispose();
      });

      final tracks = [
        for (var i = 0; i < 3; i++)
          TrackNode.fromJson({
            'type': 'audio',
            'hash': '800/$i',
            'title': '0$i.mp3',
            'mediaStreamUrl': server.uri.toString(),
          }).flatten().single,
      ];
      await player.playWork(Work.fromJson({'id': 800, 'title': 'Album'}), tracks);
      final sources = audio.sources.cast<ja.UriAudioSource>();

      // Track 0 plays and caches (60 KB).
      await _readAll(sources[0].uri);
      const key0 = AudioCacheKey(
        accountScope: 'guest',
        workId: 800,
        trackId: '800/0',
        lowQuality: false,
      );
      const key1 = AudioCacheKey(
        accountScope: 'guest',
        workId: 800,
        trackId: '800/1',
        lowQuality: false,
      );
      expect(cache.isActive(key0.id), isTrue);
      expect(cache.isActive(key1.id), isFalse);

      // Advance to track 1 -> track 0 is released and evicted once track 1 caches!
      clock = clock.add(const Duration(minutes: 5));
      await player.seekToIndex(1);
      await Future<void>.delayed(Duration.zero);
      expect(cache.isActive(key0.id), isFalse);
      expect(cache.isActive(key1.id), isTrue);
      await _readAll(sources[1].uri);
      expect(await cache.lookupComplete(key0), isNull);
      expect(await cache.lookupComplete(key1), isNotNull);
      expect(cache.cachedBytes, 60 * 1024);

      // Simulate setAudioSources failure on a fresh player -> zero leaked active refs, manual clear deletes track 1.
      await player.stop();
      final failingAudio = TestAudio()..failLoading = true;
      final failingPlayer = PlayerState(
        settings: settings,
        library: TestLibrary(),
        audioPlayer: failingAudio,
        audioCache: cache,
        accountScope: () => 'guest',
      );
      addTearDown(failingPlayer.dispose);
      final res = await failingPlayer.playWork(
        Work.fromJson({'id': 800, 'title': 'Album'}),
        tracks,
        startIndex: 1,
      );
      expect(res.queued, 0);
      expect(cache.isActive(key1.id), isFalse);
      expect(await cache.clearAll(), 0);
      expect(cache.cachedBytes, 0);
    },
  );

  test(
    'concurrent requests for the same uncached track keep both streams intact and commit one reusable cache file',
    () async {
      final chunkA = Uint8List.fromList(List.filled(16 * 1024, 0xAA));
      final chunkB = Uint8List.fromList(List.filled(16 * 1024, 0xBB));
      final expected = Uint8List.fromList([...chunkA, ...chunkB]);

      final releaseFirst = Completer<void>();
      final firstHalfSent = Completer<void>();
      final secondHalfStarted = Completer<void>();
      var upstreamHits = 0;

      final gatedServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => gatedServer.close(force: true));
      gatedServer.listen((req) async {
        final hit = ++upstreamHits;
        req.response.statusCode = HttpStatus.ok;
        req.response.headers.set(HttpHeaders.contentTypeHeader, 'audio/mpeg');
        req.response.contentLength = expected.length;
        req.response.add(chunkA);
        await req.response.flush();
        if (hit == 1) {
          firstHalfSent.complete();
          await releaseFirst.future;
        } else {
          secondHalfStarted.complete();
        }
        req.response.add(chunkB);
        await req.response.close();
      });

      final dir = await Directory.systemTemp.createTemp('asmr-concurrent-');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final cache = StreamAudioCache(directoryProvider: () async => dir);
      addTearDown(cache.dispose);

      const key = AudioCacheKey(
        accountScope: 'guest',
        workId: 555,
        trackId: '555/0',
        lowQuality: false,
      );
      final upstreamUri = Uri.parse(
        'http://127.0.0.1:${gatedServer.port}/track.mp3',
      );
      final proxyUri = await cache.resolvePlayableUri(
        key: key,
        remoteUri: upstreamUri,
      );

      // Start request 1 (holds writer lock) and pause after first chunk.
      final f1 = _readAll(proxyUri!);
      await firstHalfSent.future;

      // Start request 2 while request 1 is still writing; request 2 finishes FIRST (pass-through).
      final f2 = _readAll(proxyUri);
      await secondHalfStarted.future;
      final bytes2 = await f2;
      expect(bytes2, expected);

      // Now let request 1 finish and commit.
      releaseFirst.complete();
      final bytes1 = await f1;
      expect(bytes1, expected);

      // Cache file is intact and next replay hits local file with 0 upstream requests!
      final hitsBeforeReplay = upstreamHits;
      final replayUri = await cache.resolvePlayableUri(
        key: key,
        remoteUri: upstreamUri,
      );
      expect(replayUri?.scheme, 'file');
      expect(await _readAll(replayUri!), expected);
      expect(upstreamHits, hitsBeforeReplay);
    },
  );
}
